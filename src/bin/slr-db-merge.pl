#!/usr/bin/perl
#
# Script to merge bib files into a single bib file, finding duplicate
# articles. This was to have been part of slr-review.pl, but it has
# proved too difficult to embed it in there, leading to a confusion
# of purpose for that script.

use File::Spec;
use strict;
use warnings;
use Errno;

my $dir;
BEGIN { # Sorry Doug :-)
    use File::Basename;
    $dir = dirname($0);
    push(@INC, "./$dir/lib");
}

use BibTeX;
use TextTK;
use Latin;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

sub iso_date {
    my ($sec, $min, $hr, $day, $mon, $yr) = gmtime();

    return sprintf("%04d-%02d-%02dT%02d:%02d:%02d", $yr + 1900, $mon + 1, $day, $hr, $min, $sec);
}

sub int_log2 {
    my ($n) = @_;

    return 0 if($n <= 0);

    return int(log($n) / log(2));
}

##############################################################################
#
#   #### #      ###  ####   ###  #      ####
#  #     #     #   # #   # #   # #     #    
#  #  ## #     #   # ####  ##### #      ### 
#  #   # #     #   # #   # #   # #         #
#   #### #####  ###  ####  #   # ##### #### 
#                                           
##############################################################################

my $title_decay = 0.8;      # Decay in 'count' for word match in title
my $abstract_decay = 0.95;  # Decay in 'count' for word match in abstract

my $n_author_citekey = 3;   # Maximum number of authors' surnames to include in citekey
my $n_title_citekey = 3;    # Maximum number of title words to include in citekey

my $max_year_diff = 1;      # Maximum difference in year to treat an article as
                            # the same

my $fork_err_redo_max = 100;
                            # Number of times to allow fork() to fail for
                            # reasons other than EAGAIN before croaking
my $redo_count = 0;         # Number of times we've failed to fork() for reasons
                            # other than EAGAIN


my @bibdirs = ("bibtex/scopus", "bibtex/wos");
my $merged_file = "bibtex/merged.bib";
my $dodgy_doi_file = "bibtex/dodgy-dois.csv";
my %results_files = (
    'table' => "bibtex/merge-table.tex",
    'graphs' => "bibtex/merge-results.pdf",
    'data' => "bibtex/merge-results.csv",
    'merge' => "bibtex/doi-merge-data.csv",
    'match' => "bibtex/merge-times.csv",
    'param' => "bibtex/merge-param.tex",
    'thresholds' => "bibtex/doi-field-thresholds.csv"
);
my $Rcmd = "R --no-save";

my %ignore_fields = ("note" => 1, "url" => 1);
my @ck_fields = ("author", "year", "title", "journal", "booktitle", "volume",
    "number", "pages", "abstract", "editor");
my %field_dependency = (
    "volume" => [ "journal", "booktitle" ],
    "number" => [ "journal" ],
    "pages" => [ "journal", "booktitle" ],
    "editor" => [ "booktitle" ]
);
my %numerical_field = ("year" => 1, "volume" => 1, "number" => -1, "pages" => 2);
my %textual_field = ("title" => $title_decay, "journal" => 1,
    "booktitle" => 1, "abstract" => $abstract_decay);

my %weight_field = (
    'author' => 3,
    'year' => 2,
    'title' => 5,
    'abstract' => 10,
    'journal' => 4,
    'booktitle' => 1,
    'editor' => 2,
    'volume' => 1,
    'number' => 1,
    'pages' => 1
);

my $maxproc = 7;
my $maxmem = 16000;

my @db;                     # Merged database of papers
my %doix;                   # DOI -> database index

my @sc_db;                  # Scopus database of papers
my %sc_doix;                # DOI -> Scopus database index
my %sc_dodgy_dois;

my @wos_db;                 # Web of Science database of papers
my %wos_doix;               # DOI -> Web of Science database index
my %wos_dodgy_dois;

my %used_keys;              # Citekeys used when saving data

my %data;

my %children;
my %exit_stat;

my %warnings_once;          # Warnings once so we don't get loads of the same

##############################################################################
#
#   ####  ###  #   # #   #  ###  #   # ####        #      ###  #   # #####
#  #     #   # ## ## ## ## #   # ##  # #   #       #       #   ##  # #    
#  #     #   # # # # # # # ##### # # # #   #       #       #   # # # #### 
#  #     #   # #   # #   # #   # #  ## #   #       #       #   #  ## #    
#   ####  ###  #   # #   # #   # #   # ####        #####  ###  #   # #####
#                                                                         
##############################################################################

while(scalar(@ARGV) > 0 && substr($ARGV[0], 0, 1) eq '-') {
    my $opt = shift(@ARGV);
    if($opt eq '--help' || $opt eq '-h') {
        die "Usage: $0 [--add-bibdir <dir>] [--clear-bibdirs] ",
            "[--decay-title <n in ]0, 1]>] [--decay-abstract <n in ]0, 1]>] ",
            "[--max-mem <n>] [--max-proc <n>] [--R-command <path>]",
            "[--surname-only-score <n>] [--surname-and-initials-score <n>] ",
            "[--weight <field> <n>] [--year-diff <n>] [<merged bib file>]\n";
    }
    elsif($opt eq '--add-bibdir' || $opt eq '-a') {
        push(@bibdirs, shift(@ARGV));
        if(!(-d "$bibdirs[$#bibdirs]")) {
            die "Bibdir \"$bibdirs[$#bibdirs]\" is not a directory\n";
        }
    }
    elsif($opt eq '--clear-bibdirs' || $opt eq '-c') {
        @bibdirs = ();
    }
    elsif($opt eq '--decay-title' || $opt eq '-d') {
        $title_decay = shift(@ARGV);
        if($title_decay <= 0 || $title_decay > 1) {
            die "Invalid decay-title \"$title_decay\"\n";
        }
        $textual_field{'title'} = $title_decay;
    }
    elsif($opt eq '--decay-abstract' || $opt eq '-D') {
        $abstract_decay = shift(@ARGV);
        if($abstract_decay <= 0 || $abstract_decay > 1) {
            die "Invalid decay-abstract \"$abstract_decay\"\n";
        }
        $textual_field{'abstract'} = $abstract_decay;
    }
    elsif($opt eq '--max-mem' || $opt eq '-m') {
        $maxmem = shift(@ARGV);
        if(substr($maxmem, -1) eq 'M') {
            $maxmem = substr($maxmem, 0, -1);
            $maxmem *= 1000;
        }
        elsif(substr($maxmem, -1) eq 'G') {
            $maxmem = substr($maxmem, 0, -1);
            $maxmem *= 1000000;
        }
        if($maxmem <= 0) {
            die "Invalid max-mem \"$maxmem\"\n";
        }
    }
    elsif($opt eq '--max-proc' || $opt eq '-p') {
        $maxproc = shift(@ARGV);
        if($maxproc <= 0) {
            die "Invalid max-proc \"$maxproc\"\n";
        }    
    }
    elsif($opt eq '--R-command' || $opt eq '-R') {
        $Rcmd = shift(@ARGV);
        open(R_FP, "|-", $Rcmd) or die "Cannot connect to R command $Rcmd: $!\n";
        print R_FP "q(status = 0)\n";
        close(R_FP);
    }
    elsif($opt eq '--without-R' || $opt eq '-r') {
        $Rcmd = '/usr/bin/tee slr-merge-'.&iso_date().'.R';
    }
    elsif($opt eq '--surname-only-score' || $opt eq '-s') {
        &BibTeX::set_surname_only(shift(@ARGV));
        if(&BibTeX::surname_only() < 0) {
            die "Invalid surname-only-score \"",
                &BibTeX::surname_only(), "\"\n";
        }
    }
    elsif($opt eq '--surname-and-initials-score' || $opt eq '-S') {
        &BibTeX::set_surname_and_initials(shift(@ARGV));
        if(&BibTeX::surname_and_initials() < 0) {
            die "Invalid surname-only-score \"",
                &BibTeX::surname_and_initials(), "\"\n";
        }
    }
    elsif($opt eq '--weight' || $opt eq '-w') {
        my $field = shift(@ARGV);
        die "Unrecognized field \"$field\"\n" if !exists($weight_field{$field});
        $weight_field{$field} = shift(@ARGV);
        if($weight_field{$field} < 0) {
            die "Invalid weight for field \"$field\": \"$weight_field{$field}\"\n"
        }
    }
    elsif($opt eq '--year-diff' || $opt eq '-y') {
        $max_year_diff = shift(@ARGV);
        if($max_year_diff < 0) {
            die "Invalid year-diff \"$max_year_diff\"\n";
        }
    }
    else {
        die "Unrecognized option \"$opt\" -- use $0 --help for usage\n";
    }
}

if(scalar(@ARGV) > 0) {
    $merged_file = shift(@ARGV);
}

my $measure_max_year_diff = &diff_measure($max_year_diff);

warn "PROGRESS [", &iso_date(), " -- ", &mem_use(), "]: Processed command line\n";

open(TEX, ">", $results_files{'param'})
    or die "Cannot create parameter table file \"", $results_files{'param'}, "\": $!\n";
my ($bt_sn_only, $bt_sn_init) = (&BibTeX::surname_only(), &BibTeX::surname_and_initials());
print TEX <<PARAM_TABLE;
\\begin{table}[!t]
	\\centering
	\\begin{tabular}{lrp{9cm}}
    	\\toprule
        Parameter & Value & Description \\\\
    	\\midrule
        \$c_1\$ & $bt_sn_init & Increment for each surname and initial author and/or editor match \\\\
        \$c_2\$ & $bt_sn_only & Increment for each surname only author/editor match \\\\
        \$d_\\texttt{abstract}\$ & $abstract_decay & Decay term for \\texttt{abstract} score \\\\
        \$d_\\texttt{title}\$ & $title_decay & Decay term for \\texttt{title} score \\\\
        \$w_\\texttt{abstract}\$ & $weight_field{'abstract'} & Weight applied to the normalized \\texttt{abstract} score \\\\
        \$w_\\texttt{author}\$ & $weight_field{'author'} & Weight applied to the normalized \\texttt{author} score \\\\
        \$w_\\texttt{booktitle}\$ $weight_field{'booktitle'} & Weight applied to the normalized \\texttt{booktitle} score \\\\
        \$w_\\texttt{editor}\$ & $weight_field{'editor'} & Weight applied to the normalized \\texttt{editor} score \\\\
        \$w_\\texttt{journal}\$ & $weight_field{'journal'} & Weight applied to the normalized \\texttt{journal} score \\\\
        \$w_\\texttt{number}\$ & $weight_field{'number'} & Weight applied to the normalized \\texttt{number} score \\\\
        \$w_\\texttt{pages}\$ & $weight_field{'pages'} & Weight applied to the normalized \\texttt{pages} score \\\\
        \$w_\\texttt{title}\$ & $weight_field{'title'} & Weight applied to the normalized \\texttt{title} score \\\\
        \$w_\\texttt{volume}\$ & $weight_field{'volume'} & Weight applied to the normalized \\texttt{volume} score \\\\
        \$w_\\texttt{year}\$ & $weight_field{'year'} & Weight applied to the normalized \\texttt{year} score \\\\
    	\\bottomrule			
	\\end{tabular}
	\\caption{Parameters used for automated merging of BibTeX data from Scopus and Web of Science}
	\\label{tab:merge-parameters}	
\\end{table}
PARAM_TABLE
close(TEX);

##############################################################################
#
#  ####  #####  ###  ####        #####  ###  #     #####  ####
#  #   # #     #   # #   #       #       #   #     #     #    
#  ####  ####  ##### #   #       ####    #   #     ####   ### 
#  #   # #     #   # #   #       #       #   #     #         #
#  #   # ##### #   # ####        #      ###  ##### ##### #### 
#                                                              
# Read in all the bibtex files, and store them in separate arrays, one for
# each database (WoS & Scopus), for now.
##############################################################################

my $t0 = times();
foreach my $bibdir (@bibdirs) {
    opendir(BIBDIR, $bibdir) or die "Cannot read bibtex directory $bibdir: $!\n";
    my @bibfiles = sort {$a cmp $b} grep(/\.bib$/, readdir(BIBDIR));

    foreach my $bibfile (@bibfiles) {
        my $t1 = times();
        my @papers = &BibTeX::read_bib("$bibdir/$bibfile");
        my $t2 = times();

        print "Read ", scalar(@papers), " papers from file \"$bibdir/$bibfile\" in ",
            ($t2 - $t1), " seconds \n";

        foreach my $paper (@papers) {
            my $src = &wos_or_scopus($paper);

            if(exists($paper->{'doi'})) {
                $paper->{'doi'} = &BibTeX::debibtex_doi($paper->{'doi'});
                $data{$src}->{'doi'}++;
            }

            $data{$src}->{'n'}++;

            if($src eq "WoS") {
                if(&add_paper_ck(\@wos_db, \%wos_doix, \%wos_dodgy_dois, $paper)) {
                    $data{$src}->{'unique'}++;
                }
            }
            elsif($src eq "Scopus") {
                if(&add_paper_ck(\@sc_db, \%sc_doix, \%sc_dodgy_dois, $paper)) {
                    $data{$src}->{'unique'}++;
                } 
            }
            else {
                warn "In file $bibfile, line ", $paper->{'_line'},
                    ", source of ", $paper->{'_bibtype'}, " ",
                    $paper->{'_bibkey'}, " could not be identified\n";
            }
        }
        my $t3 = times();
        print "\tProcessed in ", ($t3 - $t2), " seconds\n";
    }
}

print "Read and checked ", scalar(@wos_db), " papers from Web of Science, and ",
    scalar(@sc_db), " from Scopus, in ", ((times() - $t0) / 60), " minutes.\n",
    "\tTotal papers: ", (scalar(@wos_db) + scalar(@sc_db)), "\n";
warn "PROGRESS [", &iso_date(), " -- ", &mem_use(),
    "]: Read Web of Science and Scopus files\n";

# Make lists of papers with no (valid/usable) DOI in each database

my @sc_no_doi;
my @wos_no_doi;

foreach my $db_no_dodgy (
    ["WoS", \@wos_db, \@wos_no_doi, \%wos_dodgy_dois],
    ["Scopus", \@sc_db, \@sc_no_doi, \%sc_dodgy_dois]
) {
    my ($src, $db, $no, $dodgy) = @$db_no_dodgy;

    for(my $i = 0; $i <= $#$db; $i++) {
        if(exists($db->[$i]->{'doi'})) {
            $data{$src}->{'u-doi'}++;
            my $doi = $db->[$i]->{'doi'};
            if(exists($dodgy->{$doi})) {
                foreach my $ix (keys(%{$dodgy->{$doi}})) {
                    push(@$no, $ix);
                    $data{$src}->{'dodgy'}++;
                    # N.B. &add_paper_doi_ck() deletes $doix->{$doi}
                    # so no need to handle it here
                }
            }
        }
        else {
            push(@$no, $i);
            $data{$src}->{'no'}++;
        }
    }
}

warn "PROGRESS [", &iso_date(), " -- ", &mem_use(),
    "]: Identified papers with and without DOI\n";

##############################################################################
#
#  #   # ##### ####   #### #####       ####   ###  #####  ### 
#  ## ## #     #   # #     #           #   # #   #   #   #   #
#  # # # ####  ####  #  ## ####        #   # #####   #   #####
#  #   # #     #   # #   # #           #   # #   #   #   #   #
#  #   # ##### #   #  #### #####       ####  #   #   #   #   #
#                                                             
# Merge the data from WoS and Scopus. First, we use DOI matching, where we
# know the records are the same, to gauge the similarity of the data stored
# in the two databases. Then we use these similarities as a basis for
# estimating whether two records without DOIs in one or other database
# are the same. So-called 'dodgy' DOIs (for which too many differences in
# entry values in the same database have been found) are not used.
##############################################################################

##############################################################################
#
#  #   # ##### ####   #### #####       ####   ###  ####  ##### ####   ####
#  ## ## #     #   # #     #           #   # #   # #   # #     #   # #    
#  # # # ####  ####  #  ## ####        ####  ##### ####  ####  ####   ### 
#  #   # #     #   # #   # #           #     #   # #     #     #   #     #
#  #   # ##### #   #  #### #####       #     #   # #     ##### #   # #### 
#                                                                         
#  #   #  ###  ##### #   #       ####   ###   ###   ####
#  #   #   #     #   #   #       #   # #   #   #   #    
#  # # #   #     #   #####       #   # #   #   #    ### 
#  # # #   #     #   #   #       #   # #   #   #       #
#   # #   ###    #   #   #       ####   ###   ###  #### 
#                                                       
# First the papers with DOIs. 
##############################################################################
my $t4 = times();
my %field_threshold;
my $n_merged = 0;
my $n_more_dodgy = 0;
my $n_year_dodgy = 0;

foreach my $field (@ck_fields) {
    next if $field eq 'year';
    $field_threshold{$field} = {};
}

my $basename = pop( @{ [ split(/\//, $results_files{'merge'}) ] });
open(FP, ">", $results_files{'merge'}."-metadata.json")
    or die "Cannot create merge results metadata file \"", $results_files{'merge'},
    "-metadata.json\": $!\n";
print FP <<MERGE_METADATA;
{
    "\@context": "http://www.w3.org/ns/csvw",
    "url": "$basename",
    "dc:title": "Results of merging papers in Web of Science and Scopus with the same DOI",
    "dc:author": "ExAMPLER project team",
    "tableSchema": {
        "columns": [{
            "titles": "doi",
            "dc:description": "DOI found in Scopus and Web of Science",
        },{
            "titles": "field",
            "dc:description": "BibTeX field"
        },{
            "titles": "is.merged",
            "dc:description": "Is this result from a DOI that was merged?",
            "datatype": "boolean"
        },{
            "titles": "context",
            "dc:description": "Context of the measurement (number of words or numbers)",
            "datatype": "number"
        },{
            "titles": "measure",
            "dc:description": "A measurement reading in this context",
            "datatype": "number"
        },{
            "titles: "is.new.min",
            "dc:description": "Is this new minimum measure for the field and context given earlier lines in the file?",
            "datatype": "boolean",
            "null": "NA",
        }]
    }
}
MERGE_METADATA
close(FP);
open(FP, ">", $results_files{'merge'})
    or die "Cannot open merge results file \"", $results_files{'merge'}, "\": $!\n";
print FP "doi,field,is.merged,context,measure,is.new.min\n";

foreach my $doi (keys(%wos_doix)) {
    my $wos_paper = $wos_db[$wos_doix{$doi}];
    if(exists($sc_doix{$doi})) {
        my $sc_paper = $sc_db[$sc_doix{$doi}];

        # Use merge_test to find out the various (mis)matches
        my $merge_result = &merge_test($wos_paper, $sc_paper);

        my $year_result = $merge_result->{'year'};
        my ($year_m, $year_s) = &field_summary('year', @$year_result);

        if($year_result->[1] > $max_year_diff || $year_result->[1] < 0) {
            print FP "\"$doi\",year,false,$year_s,$year_m,NA\n";
            $n_more_dodgy++;
            $n_year_dodgy++;

            foreach my $field (keys(%$merge_result)) {
                next if $field eq 'year';
                my $field_result = $merge_result->{$field};
                next if scalar(@$field_result) == 0;
                my ($measure, $summary) = &field_summary($field, @$field_result);
                print FP "\"$doi\",$field,false,$summary,$measure,NA\n";
            }

            push(@wos_no_doi, $wos_doix{$doi});
            push(@sc_no_doi, $sc_doix{$doi});
            $wos_dodgy_dois{$doi}->{$wos_doix{$doi}} = -1;
            $sc_dodgy_dois{$doi}->{$sc_doix{$doi}} = -1;
            delete $wos_doix{$doi};
            delete $sc_doix{$doi};
        }
        else {
            # Year is within range: decide whether to add this DOI as a merge
            # and what to do about the threshold for each field.
            my $add_it = "true";

            my @to_print;
            my %new_threshold;
            foreach my $field (keys(%$merge_result)) {
                # We've done year already
                next if($field eq 'year');

                # Don't bother about cases where one or other paper didn't have
                # an entry for the field
                next unless(exists($wos_paper->{$field}) && exists($sc_paper->{$field}));

                my $field_result = $merge_result->{$field};
            
                next if scalar(@$field_result) == 0;

                my ($measure, $summary) = &field_summary($field, @$field_result);

                if($measure == 0) {
                    # None of the words were the same, none of the authors,
                    # or the numbers were just too different
                    $add_it = "false";
                    push(@to_print, [$doi, $field, $summary, $measure]);
                }
                else {
                    # This field won't stop us merging the paper at least
                    # -- is it a new potential threshold? Only if we'll $add_it,
                    # so keep track of which thresholds are new for when we
                    # know after all fields are done
                    die "BUG!" if(!exists($field_threshold{$field})); # Paranoia

                    my $threshold = $field_threshold{$field};

                    if(exists($threshold->{$summary})) {
                        if($measure < $threshold->{$summary}) {
                            $new_threshold{$field} = $threshold;
                        }
                    }
                    else {
                        $new_threshold{$field} = $threshold;
                    }
                    push(@to_print, [$doi, $field, $summary, $measure]);
                }
            }
            # Now save the field match data and make adjustments to the thresholds
            print FP "\"$doi\",year,$add_it,$year_s,$year_m,NA\n";
            foreach my $printable (@to_print) {
                my ($d, $f, $s, $m) = @$printable;
                my $th = "false";
                if($add_it eq "true" && exists($new_threshold{$f})) {
                    my $threshold = $new_threshold{$f};
                    $threshold->{$s} = $m;
                    $th = "true";
                }
                print FP "\"$d\",$f,$add_it,$s,$m,$th\n";
            }

            if($add_it eq "true") {
                # Add the merged paper to the merged database (@db)
                &add_paper(\@db, \%doix, &merge_doi($wos_paper, $sc_paper));
                $sc_db[$sc_doix{$doi}] = {};
                $wos_db[$wos_doix{$doi}] = {};
                $n_merged++;
            }
            else {
                # Don't add it, and don't trust the DOI
                $n_more_dodgy++;
                push(@wos_no_doi, $wos_doix{$doi});
                push(@sc_no_doi, $sc_doix{$doi});
                $wos_dodgy_dois{$doi}->{$wos_doix{$doi}} = -1;
                $sc_dodgy_dois{$doi}->{$sc_doix{$doi}} = -1;
                delete $wos_doix{$doi};
                delete $sc_doix{$doi};
            }
        }
    }
}
close(FP);
my $t5 = times();
print "Merged $n_merged papers with DOIs in ", (($t5 - $t4) / 60), " minutes\n";
print "Found $n_more_dodgy further non-unique DOIs, of which $n_year_dodgy had ",
    "year differences more than $max_year_diff\n";
print "Database size is ", scalar(@db), "\n";
foreach my $doi (keys(%wos_doix)) {
    if(!exists($sc_doix{$doi})) {
        &add_paper(\@db, \%doix, $wos_db[$wos_doix{$doi}]);
        $wos_db[$wos_doix{$doi}] = {};
        $data{'WoS'}->{'unmerged-doi'}++;
    }
}
print "Added ", $data{'WoS'}->{'unmerged-doi'}, " papers with DOIs from Web of ",
    "Science that do not appear in Scopus\n";
print "Database size is ", scalar(@db), "\n";
foreach my $doi (keys(%sc_doix)) {
    if(!exists($wos_doix{$doi})) {
        &add_paper(\@db, \%doix, $sc_db[$sc_doix{$doi}]);
        $sc_db[$sc_doix{$doi}] = {};
        $data{'Scopus'}->{'unmerged-doi'}++;
    }
}
print "Added ", $data{'Scopus'}->{'unmerged-doi'}, " papers with DOIs from Scopus ",
    "that do not appear in Web of Science\n";
print "Database size is ", scalar(@db), "\n";

warn "PROGRESS [", &iso_date(), " -- ", &mem_use(), "]: Merged papers with DOIs\n";

################################################################################
#
#  ####  ###  #   # #####       #####  ###  ##### #     #### 
# #     #   # #   # #           #       #   #     #     #   #
#  ###  ##### #   # ####        ####    #   ####  #     #   #
#     # #   #  # #  #           #       #   #     #     #   #
# ####  #   #   #   #####       #      ###  ##### ##### #### 
#                                                            
# ##### #   # ####  #####  #### #   #  ###  #     ####   ####
#   #   #   # #   # #     #     #   # #   # #     #   # #    
#   #   ##### ####  ####   ###  ##### #   # #     #   #  ### 
#   #   #   # #   # #         # #   # #   # #     #   #     #
#   #   #   # #   # ##### ####  #   #  ###  ##### ####  #### 
#                                                            
################################################################################

$basename = pop( @{ [ split(/\//, $results_files{'thresholds'}) ] });
open(FP, ">", $results_files{'thresholds'}."-metadata.json")
    or die "Cannot create field threshold results metadata file \"", $results_files{'thresholds'},
    "-metadata.json\": $!\n";
print FP <<THRESHOLD_METADATA;
{
    "\@context": "http://www.w3.org/ns/csvw",
    "url": "$basename",
    "dc:title": "Field thresholds obtained from Web of Science and Scopus papers with the same DOI",
    "dc:author": "ExAMPLER project team",
    "tableSchema": {
        "columns": [{
            "titles": "field",
            "dc:description": "BibTeX field"
        },{
            "titles": "context",
            "dc:description": "Context of the threshold (number of words or numbers)",
            "datatype": "number"
        },{
            "titles": "threshold",
            "dc:description": "Minimum (threshold) measurement reading in this context",
            "datatype": "number"
        }]
    }
}
THRESHOLD_METADATA
close(FP);
open(FP, ">", $results_files{'thresholds'})
    or die "Cannot open field threshold results file \"", $results_files{'thresholds'}, "\": $!\n";
print FP "field,context,threshold\n";
foreach my $field (sort {$a cmp $b} keys(%field_threshold)) {
    my $threshold = $field_threshold{$field};
    foreach my $context (sort {$a <=> $b} keys(%$threshold)) {
        print FP "$field,$context,", $threshold->{$context}, "\n";
    }
}
close(FP);

##############################################################################
#
#   ####  ###  #   # #####       ####   ###  ####   #### #   #       ####   ###   ###   ####
#  #     #   # #   # #           #   # #   # #   # #      # #        #   # #   #   #   #    
#   ###  ##### #   # ####        #   # #   # #   # #  ##   #         #   # #   #   #    ### 
#      # #   #  # #  #           #   # #   # #   # #   #   #         #   # #   #   #       #
#  ####  #   #   #   #####       ####   ###  ####   ####   #         ####   ###   ###  #### 
#                                                                                           
# Save a list of dodgy DOIs
##############################################################################

my %all_dodgy_dois;
foreach my $doi (keys(%sc_dodgy_dois), keys(%wos_dodgy_dois)) {
    $all_dodgy_dois{$doi}++;
}

$basename = pop( @{ [ split(/\//, $dodgy_doi_file) ] });
open(FP, ">", $dodgy_doi_file."-metadata.json")
    or die "Cannot create dodgy DOI metadata file \"", $dodgy_doi_file,
    "-metadata.json\": $!\n";
print FP <<DODGY_METADATA;
{
    "\@context": "http://www.w3.org/ns/csvw",
    "url": "$basename",
    "dc:title": "List of DOIs found either not to be unique, or believed to be mis-entered",
    "dc:author": "ExAMPLER project team",
    "tableSchema": {
        "columns": [{
            "titles": "doi",
            "dc:description": "DOI found in Scopus and/or Web of Science",
        },{
            "titles": "n.scopus",
            "dc:description": "Number of times this DOI was found in Scopus"
            "datatype": "integer"
        },{
            "titles": "n.wos",
            "dc:description": "Number of times this DOI was found in Web of Science",
            "datatype": "integer"
        },{
            "titles": "n.unmerged",
            "dc:description": "Number of times this DOI was not merged because the difference in year was more than $max_year_diff",
            "datatype": "integer"
        }]
    }
}
DODGY_METADATA
close(FP);
open(FP, ">", $dodgy_doi_file)
    or die "Cannot open dodgy DOI file \"$dodgy_doi_file\": $!\n";
print FP "doi,n.scopus,n.wos,n.unmerged\n";
foreach my $doi (keys(%all_dodgy_dois)) {
    my ($n_sc, $n_wos, $n_both) = (0, 0, 0);
    my $is_wos = exists($wos_dodgy_dois{$doi});
    my $is_sc = exists($sc_dodgy_dois{$doi});
    if($is_sc) {
        foreach my $sc_ix (keys(%{$sc_dodgy_dois{$doi}})) {
            $n_sc++;
            if($is_wos) {
                $n_both++;
                $sc_db[$sc_ix]->{'_dodgy_doi'} = 'Both';
            }
            else {
                $sc_db[$sc_ix]->{'_dodgy_doi'} = 'Scopus';
            }
        }
    }
    if($is_wos) {
        foreach my $wos_ix (keys(%{$wos_dodgy_dois{$doi}})) {
            $n_wos++;
            if($is_sc) {                
                # Don't add to $n_both because we will already have
                # counted the paper in Scopus
                $wos_db[$wos_ix]->{'_dodgy_doi'} = 'Both';
            }
            else {
                $wos_db[$wos_ix]->{'_dodgy_doi'} = 'WoS';
            }
        }
    }
    $doi =~ s/\"/\"\"/g;
    print FP "\"$doi\",$n_sc,$n_wos,$n_both\n";
}
close(FP);
undef %all_dodgy_dois;
undef %wos_dodgy_dois;
undef %sc_dodgy_dois;

warn "PROGRESS [", &iso_date(), " -- ", &mem_use(), "]: Saved dodgy DOIs\n";

##############################################################################
#
#  #   #  ###  #####  #### #   #       ####   ###  ####  ##### ####   ####
#  ## ## #   #   #   #     #   #       #   # #   # #   # #     #   # #    
#  # # # #####   #   #     #####       ####  ##### ####  ####  ####   ### 
#  #   # #   #   #   #     #   #       #     #   # #     #     #   #     #
#  #   # #   #   #    #### #   #       #     #   # #     ##### #   # #### 
#                                                                         
#  #   #  ###  ##### #   #  ###  #   # #####       ####   ###   ###   ####
#  #   #   #     #   #   # #   # #   #   #         #   # #   #   #   #    
#  # # #   #     #   ##### #   # #   #   #         #   # #   #   #    ### 
#  # # #   #     #   #   # #   # #   #   #         #   # #   #   #       #
#   # #   ###    #   #   #  ###   ###    #         ####   ###   ###  #### 
#                                                                         
# For the papers with no DOI, build up a match picture. To cut down on time,
# we do this in two steps, one of which is to check that the title meets 
# $field_thresholds{'title'}; the other is only to iterate through papers
# with a year within range.
##############################################################################

my %wos_years;
foreach my $wos_ix (@wos_no_doi) {
    my $wos_paper = $wos_db[$wos_ix];

    if(exists($wos_paper->{'year'})) {
        my $year = $wos_paper->{'year'};
        for(my $y = $year - $max_year_diff; $y <= $year + $max_year_diff; $y++) {
            push(@{$wos_years{$y}}, $wos_ix);
        }
    }
}
warn "PROGRESS [", &iso_date(), " -- ", &mem_use(),
    "]: Identified Web of Science papers within +/- $max_year_diff of each year\n";


my %wos_match;  # Best matching papers for each WoS (WoS ix -> Scopus ix -> {match data})
my %sc_match;   # Best matching papers for each Scopus (Scopus ix -> WoS ix -> {match data}])
my $i_sc = 0;
my $t6 = times();

my $csv_fp;

$basename = pop( @{ [ split(/\//, $results_files{'match'}) ] });
open(FP, ">", $results_files{'match'}."-metadata.json")
    or die "Cannot create match timings results metadata file \"", $results_files{'match'},
    "-metadata.json\": $!\n";
print FP <<MATCH_METADATA;
{
    "\@context": "http://www.w3.org/ns/csvw",
    "url": "$basename",
    "dc:title": "Timing results from matching papers without a DOI in Web of Science and Scopus",
    "dc:author": "ExAMPLER project team",
    "tableSchema": {
        "columns": [{
            "titles": "PID",
            "dc:description": "Process ID used to calculate the match"
        },{
            "titles": "exit",
            "null": "NA",
            "dc:description": "Exit status of the process if non-zero"
        },{
            "titles": "n.WoS",
            "dc:description": "Number of papers in Web of Science explored by child process",
            "null": "NA",
            "datatype": "integer",
        },{
            "titles": "time.secs",
            "dc:description": "CPU time in seconds (from scalar Perl times() procedure)",
            "https://sdmx.org/wp-content/uploads/SDMX_Glossary_Version_2_1_December_2020.htm#_Toc59019175": {
                "\@id": "http://qudt.org/vocab/unit/SEC"
            }
            "null": "NA",
            "datatype": "number"
        },{
            "titles": "size.Mb",
            "dc:description": "Megabytes of memory used by forked process at time of saving file",
            "https://sdmx.org/wp-content/uploads/SDMX_Glossary_Version_2_1_December_2020.htm#_Toc59019175": {
                "\@id": "http://qudt.org/vocab/unit/SEC"
            }
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "peak.Mb",
            "dc:description": "Peak megabytes of memory used by forked process",
            "https://sdmx.org/wp-content/uploads/SDMX_Glossary_Version_2_1_December_2020.htm#_Toc59019175": {
                "\@id": "http://qudt.org/vocab/unit/SEC"
            }
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "free.Mb",
            "dc:description": "Megabytes of memory free on host machine",
            "https://sdmx.org/wp-content/uploads/SDMX_Glossary_Version_2_1_December_2020.htm#_Toc59019175": {
                "\@id": "http://qudt.org/vocab/unit/SEC"
            }
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "avail.Mb",
            "dc:description": "Megabytes of memory available on host machine",
            "https://sdmx.org/wp-content/uploads/SDMX_Glossary_Version_2_1_December_2020.htm#_Toc59019175": {
                "\@id": "http://qudt.org/vocab/unit/SEC"
            }
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "n.scopus.read",
            "dc:description": "Number of Scopus indexes read from child (expecting 1)",
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "n.WoS.read",
            "dc:description": "Number of Web of Science indexes read from child (expecting n.WoS)",
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "n.accepted",
            "dc:description": "Number of accepted matches (that met thresholds)",
            "null": "NA",
            "datatype": "integer"
        }.{
            "titles": "n.fields",
            "dc:description": "Number of field comparisons made over all records",
            "null": "NA",
            "datatype": "integer"
        },{
            "titles": "n.fld.acc",
            "dc:description": "Number of field comparisons made over accepted matches",
            "null": "NA",
            "datatype": "integer"
        }]
    }
}
MATCH_METADATA
close(FP);
open($csv_fp, ">", $results_files{'match'})
    or die "Cannot create match timings results file ", $results_files{'match'},
        ": $!\n";
print $csv_fp "PID,exit,n.WoS,time.secs,size.Mb,peak.Mb,free.Mb,avail.Mb,",
    "n.scopus.read,n.WoS.read,n.accepted,n.fields,n.fld.acc\n";
foreach my $sc_ix (@sc_no_doi) {
    $i_sc++;
    my $sc_paper = $sc_db[$sc_ix];

    next if (!exists($sc_paper->{'year'}) || !exists($sc_paper->{'title'}));

    my @pids = &match_scopus($csv_fp, $maxproc, $maxmem, \%children, \%exit_stat, $sc_ix,
        $sc_paper, \%sc_match, \%wos_match, \@wos_db, \%wos_years, \%field_threshold);
    foreach my $pid (@pids) {
        if($exit_stat{$pid} != 0) {
            print $csv_fp "$pid,", $exit_stat{$pid}, ",NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA\n";
        } 
    }
}
# Harvest the remaining children
foreach my $pid (&wait_for($csv_fp, 0, $maxmem, \%children, \%exit_stat,
    \%wos_match, \%sc_match, \%field_threshold)
) {
    if($exit_stat{$pid} != 0) {
        print $csv_fp "$pid,", $exit_stat{$pid}, ",NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA\n";
    }    
}
close($csv_fp);

undef %exit_stat;

##############################################################################
#
#  #   # ##### ####   #### #####       #   #  ###        ####   ###   ### 
#  ## ## #     #   # #     #           ##  # #   #       #   # #   #   #  
#  # # # ####  ####  #  ## ####        # # # #   #       #   # #   #   #  
#  #   # #     #   # #   # #           #  ## #   #       #   # #   #   #  
#  #   # ##### #   #  #### #####       #   #  ###        ####   ###   ### 
#                                                                         
#  #   #  ###  #####  #### #   # #####  ####
#  ## ## #   #   #   #     #   # #     #    
#  # # # #####   #   #     ##### ####   ### 
#  #   # #   #   #   #     #   # #         #
#  #   # #   #   #    #### #   # ##### #### 
#                                           
##############################################################################


my $t8 = times();
print "Checked ", scalar(@wos_no_doi), " Web of Science papers with no DOI against ",
    scalar(@sc_no_doi), " Scopus papers with no DOI in ", (($t8 - $t6) / 60),
    " minutes\n";
warn "PROGRESS [", &iso_date(), " -- ", &mem_use(), "]: Completed parallel no DOI merge\n";

# Now add them to the database

my %wos_merged;
$n_merged = 0;
foreach my $sc_ix (@sc_no_doi) {
    my @wos_ixes;
    
    # Check which WoS papers on the Scopus paper's pareto front
    # meet the minimum conditions for two papers with DOIs to be
    # merged
    if(exists($sc_match{$sc_ix})) {
        foreach my $wos_ix (keys %{$sc_match{$sc_ix}}) {
            # The Scopus paper must also be on the WoS paper's pareto front
            push(@wos_ixes, $wos_ix) if(exists($wos_match{$wos_ix}->{$sc_ix}));
        }
    }
    # If it has a good enough match with a wos_ix, merge that
    if(scalar(@wos_ixes) > 0) {
        # Do the merge with the best paper
        my $wos_ix = shift(@wos_ixes);
        foreach my $other_wos_ix (@wos_ixes) {
            if(&better_match($sc_match{$sc_ix}->{$other_wos_ix},
                $sc_match{$sc_ix}->{$wos_ix})
            ) {
                $wos_ix = $other_wos_ix;
            }
        }

        # Add the merged paper to the database -- note we send an empty
        # hash instead of \%doix because we already know this DOI is not
        # usable or not present, so no point indexing on it
        &add_paper(\@db, {}, &merge_no_doi($sc_db[$sc_ix], $wos_db[$wos_ix]));
        $wos_merged{$wos_ix} = 1;
        $n_merged++;
    }
    else {
        # Else save the paper to the database
        &add_paper(\@db, {}, $sc_db[$sc_ix]);
        $data{'Scopus'}->{'unmerged-no-doi'}++;
    }
}

foreach my $wos_ix (@wos_no_doi) {
    # If it wasn't merged before then add it
    if(!exists($wos_merged{$wos_ix})) {
        &add_paper(\@db, {}, $wos_db[$wos_ix]);
        $data{'WoS'}->{'unmerged-no-doi'}++;
    }
}

my $t9 = times();
print "Merged $n_merged further papers with no usable DOI in ", ($t9 - $t8),
    " seconds.\n";
print "Added ", $data{'WoS'}->{'unmerged-no-doi'}, " papers with no usable ",
    "DOIs from Web of Science that could not be matched with an entry ",
    "in Scopus\n";
print "Added ", $data{'Scopus'}->{'unmerged-no-doi'}, " papers with no usable ",
    "DOIs from Scopus that could not be matched with an entry in Web of ",
    "Science\n";
print "Database size is ", scalar(@db), "\n";

warn "PROGRESS [", &iso_date(), " -- ", &mem_use(), "]: Merged papers with no DOI\n";

##############################################################################
#
#   ####  ###  #   # #####       ####  #### 
#  #     #   # #   # #           #   # #   #
#   ###  ##### #   # ####        #   # #### 
#      # #   #  # #  #           #   # #   #
#  ####  #   #   #   #####       ####  #### 
#                                           
##############################################################################

$basename = pop( @{ [ split(/\//, $results_files{'data'}) ] });
open(FP, ">", $results_files{'data'}."-metadata.json")
    or die "Cannot create data metadata file \"", $results_files{'data'},
    "-metadata.json\": $!\n";
print FP <<DATA_METADATA;
{
    "\@context": "http://www.w3.org/ns/csvw",
    "url": "$basename",
    "dc:title": "Field thresholds",
    "dc:author": "ExAMPLER project team",
    "tableSchema": {
        "columns": [{
            "titles": "Field",
            "dc:description": "BibTeX field for which threshold applies"
        },{
            "titles": "Context",
            "dc:description": "Contextual data for the applicable threshold (number of words or numbers)",
            "datatype": "number"
        },{
            "titles": "Threshold",
            "dc:description": "Minimum measurement in the context for this field for two papers to be considered the same"
            "datatype": "number"
        }]
    }
}
DATA_METADATA
close(FP);
open(FP, ">", $results_files{'data'})
    or die "Cannot open data file ", $results_files{'data'}, ": $!\n";
open(R_FP, "|-", $Rcmd) or die "Cannot connect to R command $Rcmd: $!\n";

print FP "Field,Context,Threshold\n";
print R_FP "pdf(\"", $results_files{'graphs'}, "\")\n";

foreach my $field (sort {$a cmp $b} keys(%field_threshold)) {
    my @summaries = sort {$a <=> $b} keys(%{$field_threshold{$field}});
    if(scalar(@summaries > 0)) {
        print R_FP "s.$field <- c(", join(", ", @summaries), ")\n";
        my @measures;
        foreach my $summary (@summaries) {
            my $measure = $field_threshold{$field}->{$summary};
            push(@measures, $measure);

            print FP "$field,$summary,$measure\n";
        }
        print R_FP "m.$field <- c(", join(", ", @measures), ")\n";
        print R_FP "plot(s.$field, m.$field, main = \"$field\", xlab = \"context\", ",
            "ylab = \"threshold\", pch = 20)\n";
    }
}
print R_FP "dev.off()\nq(status = 0)\n";

close(R_FP);
close(FP);
&report_tables($results_files{'table'});
&choose_merged(\@db);
&save_bib(\@db, $merged_file);

my $t10 = times();
print "Saved database and reports in ", ($t10 - $t9), " seconds.\n",
    "Total elapsed time ", (($t10 - $t0) / 3600), " hours.\nExiting.\n";
warn "PROGRESS [", &iso_date(), " -- ", &mem_use(), "]: Saved all reports\n";


##############################################################################
#
#  ##### #   #  ###  #####
#  #      # #    #     #  
#  ####    #     #     #  
#  #      # #    #     #  
#  ##### #   #  ###    #  
#                         
##############################################################################

exit 0;

##############################################################################
#
#   ###  ####  ####        ####   ###  ####  ##### #### 
#  #   # #   # #   #       #   # #   # #   # #     #   #
#  ##### #   # #   #       ####  ##### ####  ####  #### 
#  #   # #   # #   #       #     #   # #     #     #   #
#  #   # ####  ####        #     #   # #     ##### #   #
#                    #####                              
#                                                       
# Add a paper to the database, updating the DOI index on the database if it
# has a DOI.
##############################################################################

sub add_paper {
    my ($db, $doix, $paper) = @_;

    push(@$db, $paper);
    
    if(exists($paper->{'doi'})) {
        $doix->{$paper->{'doi'}} = $#$db;
    }

}

##############################################################################
#
#   ###  ####  ####        ####   ###  ####  ##### ####         #### #   #
#  #   # #   # #   #       #   # #   # #   # #     #   #       #     #  # 
#  ##### #   # #   #       ####  ##### ####  ####  ####        #     ###  
#  #   # #   # #   #       #     #   # #     #     #   #       #     #  # 
#  #   # ####  ####        #     #   # #     ##### #   #        #### #   #
#                    #####                               #####            
#                                                                         
# Check for duplicates before adding a paper to the database
##############################################################################

sub add_paper_ck {
    my ($db, $doix, $dodgy, $paper) = @_;

    if(exists($paper->{'doi'})) {
        if(exists($doix->{$paper->{'doi'}})) {
            # We've got the DOI already; check it's the same
            # data as the DOI we've already got, and handle
            # the situation accordingly
            return &add_paper_doi_ck($db, $doix, $dodgy, $paper);
        }
        elsif(exists($dodgy->{$paper->{'doi'}})) {
            # We've got the DOI already, but we already know
            # that this DOI is associated with different records,
            # so handle that situation
            return &add_paper_dodgy_doi_ck($db, $dodgy, $paper);
        }
        else {
            # The paper has a DOI, but we have not added that DOI to
            # the database yet, so do so.
            &add_paper($db, $doix, $paper);
            return 1;
        }
    }
    elsif(&search_db($db, $paper) >= 0) {
        # The paper has no DOI, but we can find something _very_
        # similar (also without a DOI) in the database already
        return 0;
    }
    else {
        # The paper has no DOI, and there is nothing like it 
        # in the database already, so add it
        &add_paper($db, $doix, $paper);
        return 1;
    }
}

##############################################################################
#
#   ###  ####  ####        ####   ###  ####  ##### ####        ####   ###   ### 
#  #   # #   # #   #       #   # #   # #   # #     #   #       #   # #   #   #  
#  ##### #   # #   #       ####  ##### ####  ####  ####        #   # #   #   #  
#  #   # #   # #   #       #     #   # #     #     #   #       #   # #   #   #  
#  #   # ####  ####        #     #   # #     ##### #   #       ####   ###   ### 
#                    #####                               #####                  
#                                                                               
#         #### #   #
#        #     #  # 
#        #     ###  
#        #     #  # 
#         #### #   #
#  #####            
#                   
# _Possibly_ add a paper with a DOI to the database, where it is known that
# the database already has an entry with that DOI.
##############################################################################

sub add_paper_doi_ck {
    my ($db, $doix, $dodgy, $paper) = @_;

    my $prev_paper = $db->[$doix->{$paper->{'doi'}}];
    my $rec_eq = &record_eq($paper, $prev_paper);

    if($rec_eq == 0) {
        if(&record_ck_eq($paper, $prev_paper)) {
            # All the fields we think are important are the same
            # We will treat this as not being a new record
            &remove_ne_fields($prev_paper, $paper);
            return 0;
        }
        else {
            # It's most probably different -- add it to the database
            # but don't use &add_paper(), which will update %$doix
            push(@$db, $paper);
            $dodgy->{$paper->{'doi'}}->{$#$db} = 1;
            $dodgy->{$paper->{'doi'}}->{$doix->{$paper->{'doi'}}} = 1;
            delete $doix->{$paper->{'doi'}};

            return 1;
        }
    }
    elsif($rec_eq == -1) {
        # It's the same, give or take a few missing fields
        &merge_missing_fields($prev_paper, $paper);
        return 0;
    }
    else {
        # They were exactly equal
        return 0;
    }
}

##############################################################################
#
#   ###  ####  ####        ####   ###  ####  ##### #### 
#  #   # #   # #   #       #   # #   # #   # #     #   #
#  ##### #   # #   #       ####  ##### ####  ####  #### 
#  #   # #   # #   #       #     #   # #     #     #   #
#  #   # ####  ####        #     #   # #     ##### #   #
#                    #####                              
#                                                       
#        ####   ###  ####   #### #   #       ####   ###   ###         #### #   #
#        #   # #   # #   # #      # #        #   # #   #   #         #     #  # 
#        #   # #   # #   # #  ##   #         #   # #   #   #         #     ###  
#        #   # #   # #   # #   #   #         #   # #   #   #         #     #  # 
#        ####   ###  ####   ####   #         ####   ###   ###         #### #   #
#  #####                               #####                   #####            
#                                                                               
# Here we know a DOI is already associated with records that have different
# enough entries we would not treat them as being the same. If we cannot find
# an existing entry with sufficient similarity, we will have to add this paper
# as well.
##############################################################################

sub add_paper_dodgy_doi_ck {
    my ($db, $dodgy, $paper) = @_;

    foreach my $prev_ix (keys(%{$dodgy->{$paper->{'doi'}}})) {
        my $prev_paper = $db->[$prev_ix];
        my $rec_eq = &record_eq($paper, $prev_paper);
        if($rec_eq == 1) {
            return 0;
        }
        elsif($rec_eq == -1) {
            &merge_missing_fields($prev_paper, $paper);
            return 0;
        }
        elsif(&record_ck_eq($paper, $prev_paper)) {
            &remove_ne_fields($prev_paper, $paper);
            return 0;
        }
    }

    # If we get here we have found _another_ paper with the
    # same DOI and different entries to any of the other
    # DOIs we have found

    push(@$db, $paper);
    $dodgy->{$paper->{'doi'}}->{$#$db} = 1;

    return 1;
}

##############################################################################
#
#  #   # ##### ####   #### #####       #   #  ###   ####  ####  ###  #   #  ####
#  ## ## #     #   # #     #           ## ##   #   #     #       #   ##  # #    
#  # # # ####  ####  #  ## ####        # # #   #    ###   ###    #   # # # #  ##
#  #   # #     #   # #   # #           #   #   #       #     #   #   #  ## #   #
#  #   # ##### #   #  #### #####       #   #  ###  ####  ####   ###  #   #  ####
#                                #####                                          
#                                                                               
#        #####  ###  ##### #     ####   ####
#        #       #   #     #     #   # #    
#        ####    #   ####  #     #   #  ### 
#        #       #   #     #     #   #     #
#        #      ###  ##### ##### ####  #### 
#  #####                                    
#                                           
# Two papers, assumed to essentially be the same one, are updated so that the
# entry in the database includes values for any fields that it doesn't already
# have.
##############################################################################

sub merge_missing_fields {
    my ($prev_paper, $paper) = @_;

    foreach my $field (keys(%$paper)) {
        if(!exists($prev_paper->{$field})) {
            $prev_paper->{$field} = $paper->{$field};
        }
        elsif($field =~ /^_/ && $paper->{$field} ne $prev_paper->{$field}) {
            $prev_paper->{$field} .= " AND ".$paper->{$field};
        }
    }
}

##############################################################################
#
#  ####  ##### #   #  ###  #   # #####       #   # #####
#  #   # #     ## ## #   # #   # #           ##  # #    
#  ####  ####  # # # #   # #   # ####        # # # #### 
#  #   # #     #   # #   #  # #  #           #  ## #    
#  #   # ##### #   #  ###    #   #####       #   # #####
#                                      #####            
#                                                       
#        #####  ###  ##### #     ####   ####
#        #       #   #     #     #   # #    
#        ####    #   ####  #     #   #  ### 
#        #       #   #     #     #   #     #
#        #      ###  ##### ##### ####  #### 
#  #####                                    
#                                           
# Two papers, near enough to being the same one, are updated such that the
# entry in the database has values removed for fields with different values.
##############################################################################

sub remove_ne_fields {
    my ($prev_paper, $paper) = @_;

    foreach my $field (keys(%$paper)) {
        if(exists($prev_paper->{$field})) {
            if(lc($prev_paper->{$field}) ne lc($paper->{$field})) {
                if($field =~ /^_/) {
                    $prev_paper->{$field} .= " AND ".$paper->{$field};
                }
                else {
                    delete $prev_paper->{$field};
                }
            }
        }
        else {
            $prev_paper->{$field} = $paper->{$field};
        }
    }
}

##############################################################################
#
#   #### #####  ###  ####   #### #   #       ####  #### 
#  #     #     #   # #   # #     #   #       #   # #   #
#   ###  ####  ##### ####  #     #####       #   # #### 
#      # #     #   # #   # #     #   #       #   # #   #
#  ####  ##### #   # #   #  #### #   #       ####  #### 
#                                      #####            
#                                                       
# Search a database for a paper that is, in essence, the same record. We
# expect it to have the same fields, and the same values for each field,
# allowing for case insensitivity in all fields
##############################################################################

sub search_db {
    my ($db, $paper, $ck_doi) = @_;

    $ck_doi = 0 if !defined($ck_doi);
    my $ix = -1;
    for(my $i = 0; $i <= $#$db; $i++) {
        next if(!$ck_doi && defined($db->[$i]->{'doi'}));

        if(&record_eq($db->[$i], $paper) != 0) {
            if($ix == -1) {
                $ix = $i;
            }
            else {
                warn "Found second duplicate for a paper in database ",
                    &wos_or_scopus($paper), "\n";
                foreach my $ck ($db->[$ix], $db->[$i], $paper) {
                    warn "\t", &paper_info($ck), "\n";
                }
            }
        }
    }

    return $ix;
}

##############################################################################
#
#  ####  #####  ####  ###  ####  ####        #####  ### 
#  #   # #     #     #   # #   # #   #       #     #   #
#  ####  ####  #     #   # ####  #   #       ####  # # #
#  #   # #     #     #   # #   # #   #       #     #  ##
#  #   # #####  ####  ###  #   # ####        #####  ####
#                                      #####            
#                                                       
# Are two papers essentially the same record? We generously ignore case and
# some fields we do not care about.
##############################################################################

sub record_eq {
    my ($a, $b) = @_;

    my $retval = 1;
    foreach my $field (keys(%$a)) {
        next if($field =~ /^_/);
        next if(exists($ignore_fields{$field}));

        if(exists($b->{$field})) {
            if(lc($a->{$field}) ne lc($b->{$field})) {
                return 0;
            }
        }
        else {
            $retval = -1;
        }
    }
    foreach my $field (keys(%$b)) {
        if($field !~ /^_/ && !exists($a->{$field})) {
            $retval = -1;
        }
    }
    return $retval;
}

##############################################################################
#  ####  #####  ####  ###  ####  ####         #### #   #       #####  ### 
#  #   # #     #     #   # #   # #   #       #     #  #        #     #   #
#  ####  ####  #     #   # ####  #   #       #     ###         ####  # # #
#  #   # #     #     #   # #   # #   #       #     #  #        #     #  ##
#  #   # #####  ####  ###  #   # ####         #### #   #       #####  ####
#                                      #####             #####            
#                                                                         
# Following a check using &record_eq() that returned 0, this procedure can be
# called to find out if the fields that are important enough to us are
# different. Because we have already found fields with different values, and
# are suspicious $a and $b are not the same record, we will assume the
# records are different if $a has an entry for an important field that $b
# has no entry for, and vice versa. Except for 'abstract', which in some
# Scopus files has not been downloaded.
##############################################################################

sub record_ck_eq {
    my ($a, $b) = @_;

    foreach my $field (@ck_fields) {
        if(exists($a->{$field}) && exists($b->{$field})) {
            if(lc($a->{$field}) ne lc($b->{$field})) {
                return 0;
            }
        }
        elsif($field ne 'abstract'
            && (exists($a->{$field}) || exists($b->{$field})))
        {
            return 0;
        }
    }
    return 1;
}

##############################################################################
# merge_test($bib1, $bib2)
#
#  #   # ##### ####   #### #####       ##### #####  #### #####
#  ## ## #     #   # #     #             #   #     #       #  
#  # # # ####  ####  #  ## ####          #   ####   ###    #  
#  #   # #     #   # #   # #             #   #         #   #  
#  #   # ##### #   #  #### #####         #   ##### ####    #  
#                                #####                        
#                                                             
# Provide summarize of how similar two records are. We are going to check
# the authors, year, title, journal, booktitle, volume, number, pages, editor
# and abstract
##############################################################################

sub merge_test {
    my ($bib1, $bib2) = @_;

    my $results = {};

    foreach my $field (@ck_fields) {
        if(exists($field_dependency{$field})) {
            my $ok = 1;
            foreach my $dependency (@{$field_dependency{$field}}) {
                if(!exists($bib1->{$dependency}) && !exists($bib2->{$dependency})) {
                    $ok = 0;
                }
            }
            if($ok) {
                $results->{$field} = &field_match($field, $bib1, $bib2);
            }
            else {
                $results->{$field} = [];
            }
        }
        else {
            $results->{$field} = &field_match($field, $bib1, $bib2);
        }
    }
    
    return $results;
}

##############################################################################
#
#  #####  ###  ##### #     #####        ###  #   #
#    #     #     #   #     #           #   # #  # 
#    #     #     #   #     ####        #   # ###  
#    #     #     #   #     #           #   # #  # 
#    #    ###    #   ##### #####        ###  #   #
#                                #####            
#                                                 
##############################################################################

sub title_ok {
    my ($bib1, $bib2, $thresholds) = @_;

    if(!exists($bib1->{'title'}) || !exists($bib2->{'title'})) {
        return 0;
    }
    my $title_match = &field_match('title', $bib1, $bib2);
    my ($measure, $summary) = &field_summary('title', @$title_match);
    return &meets_threshold('title', $summary, $measure, $thresholds);
}

##############################################################################
#
#  #   # ##### ##### #####  ####       ##### #   # ####  #####  #### #   #  ###  #     #### 
#  ## ## #     #       #   #             #   #   # #   # #     #     #   # #   # #     #   #
#  # # # ####  ####    #    ###          #   ##### ####  ####   ###  ##### #   # #     #   #
#  #   # #     #       #       #         #   #   # #   # #         # #   # #   # #     #   #
#  #   # ##### #####   #   ####          #   #   # #   # ##### ####  #   #  ###  ##### #### 
#                                #####                                                      
#                                                                                           
##############################################################################

sub meets_threshold {
    my ($field, $summary, $measure, $thresholds) = @_;

    if($field eq 'year') {
        return ($measure >= $measure_max_year_diff);
    }
    elsif(!exists($thresholds->{$field}) || scalar(keys(%{$thresholds->{$field}})) == 0) {
        if(!exists($warnings_once{"threshold$field"})) {
            warn "No threshold defined for field \"$field\"\n";
            $warnings_once{"threshold$field"} = 1;
        }
        return 1;
    }

    if(exists($thresholds->{$field}->{$summary})) {
        if($measure < $thresholds->{$field}->{$summary}) {
            return 0;
        }
    }
    else {
        my $nearest_summary;
        my $nearest_distance;
        foreach my $key (keys(%{$thresholds->{$field}})) {
            if(defined($nearest_summary)) {
                if(abs($key - $summary) < $nearest_distance) {
                    $nearest_summary = $key;
                    $nearest_distance = abs($key - $summary);
                }
            }
            else {
                $nearest_summary = $key;
                $nearest_distance = abs($key - $summary);
            }
        }
        if($measure < $thresholds->{$field}->{$nearest_summary}) {
            return 0;
        }
    }
    return 1;
}

##############################################################################
#
#  #####  ###  #     ##### ##### ####        #   #  ###  #####  #### #   # #####  ####
#  #       #   #       #   #     #   #       ## ## #   #   #   #     #   # #     #    
#  ####    #   #       #   ####  ####        # # # #####   #   #     ##### ####   ### 
#  #       #   #       #   #     #   #       #   # #   #   #   #     #   # #         #
#  #      ###  #####   #   ##### #   #       #   # #   #   #    #### #   # ##### #### 
#                                      #####                                          
#                                                                                     
##############################################################################

sub filter_matches {
    my ($matches, $thresholds) = @_;

    my @ixes;
    foreach my $ix (keys(%$matches)) {
        my ($add, $cmp) = &accept_match($matches, $thresholds);

        push(@ixes, $ix) if($add && $cmp > 0);
    }

    return @ixes;
}

##############################################################################
#
#  ####   ###  ####  ##### #####  ### 
#  #   # #   # #   # #       #   #   #
#  ####  ##### ####  ####    #   #   #
#  #     #   # #   # #       #   #   #
#  #     #   # #   # #####   #    ### 
#                                     
# Determine pareto dominance of a comparator against a set of matches stored
# in a hash ref that will have the items dominated by the comparator removed.
###############################################################################

sub pareto {
    my ($ixes, $comparator) = @_;

    my @to_delete;
    my $add = 0;
    foreach my $ix (keys(%$ixes)) {
        my $cmp = &cmp_matches($comparator, $ixes->{$ix});
        $add = 1 if($cmp != 0);
        push(@to_delete, $ix) if($cmp > 0);
    }
    foreach my $ix (@to_delete) {
        delete $ixes->{$ix};
    }
    return $add;
}

##############################################################################
#
#  ####  ##### ##### ##### ##### ####        #   #  ###  #####  #### #   #
#  #   # #       #     #   #     #   #       ## ## #   #   #   #     #   #
#  ####  ####    #     #   ####  ####        # # # #####   #   #     #####
#  #   # #       #     #   #     #   #       #   # #   #   #   #     #   #
#  ####  #####   #     #   ##### #   #       #   # #   #   #    #### #   #
#                                      #####                              
#
# Here, we prioritize field matches to return the result of a totally ordered
# comparison of two matches (unlike &pareto(), which is based on a partially
# ordered comparison). This will only return 1 if $a is strictly better than
# $b.
###############################################################################

sub better_match {
    my ($a, $b) = @_;

    # First check: fields. X is a better match than Y if Y's match fields
    # with a measured entry are a proper subset of those of X. But while
    # we're about checking the fields, we can also gather together the
    # normalized scores for fields with entries.

    my $a_C_b = 1;
    my $b_C_a = 1;
    my %score_a;
    my %score_b;
    foreach my $field (@ck_fields) {
        my $af = $a->{$field};
        my $bf = $b->{$field};

        if(scalar(@$af) > 0 && scalar(@$bf) == 0) {
            # $a's fields are not a proper subset of $b's
            $a_C_b = 0;
        }
        elsif(scalar(@$bf) > 0 && scalar(@$af) == 0) {
            # $b's fields are not a proper subset of $a's
            $b_C_a = 0;
        }
        elsif(scalar(@$af) > 0 && scalar(@$bf) > 0) {
            if(exists($numerical_field{$field})) {
                if($$af[0] >= 0 && $$bf[0] == -1) {
                    # $a has a numerical measurement when $b doesn't
                    $a_C_b = 0;
                    $score_a{$field} = &normalize_field($field, @$af);
                }
                elsif($$bf[0] >= 0 && $$af[0] == -1) {
                    # $b has a numerical measurement when $a doesn't
                    $b_C_a = 0;
                    $score_b{$field} = &normalize_field($field, @$bf);
                }
                else {
                    # May as well get the score
                    $score_a{$field} = &normalize_field($field, @$af);
                    $score_b{$field} = &normalize_field($field, @$bf);
                }
            }
            else {
                if($$af[0] > 0 && $$bf[0] == 0) {
                    $a_C_b = 0;
                    $score_a{$field} = &normalize_field($field, @$af);
                }
                elsif($$bf[0] > 0 && $$af[0] == 0) {
                    $b_C_a = 0;
                    $score_b{$field} = &normalize_field($field, @$bf);
                }
                else {
                    $score_a{$field} = &normalize_field($field, @$af);
                    $score_b{$field} = &normalize_field($field, @$bf);
                }
            }
        }
    }
    return 1 if($b_C_a && !$a_C_b);
    return 0 if($a_C_b && !$b_C_a);

    my $a_score = 0;
    my $b_score = 0;

    foreach my $field (@ck_fields) {
        if(exists($score_a{$field})) {
            $a_score += $score_a{$field} * $weight_field{$field};
        }
        if(exists($score_b{$field})) {
            $b_score += $score_b{$field} * $weight_field{$field};
        }
    }

    return ($a_score > $b_score);
}

##############################################################################
#
#  #   #  ###  ####  #   #  ###  #      ###  ##### #####       #####  ###  ##### #     #### 
#  ##  # #   # #   # ## ## #   # #       #      #  #           #       #   #     #     #   #
#  # # # #   # ####  # # # ##### #       #     #   ####        ####    #   ####  #     #   #
#  #  ## #   # #   # #   # #   # #       #    #    #           #       #   #     #     #   #
#  #   #  ###  #   # #   # #   # #####  ###  ##### #####       #      ###  ##### ##### #### 
#                                                        #####                              
#                                                                                           
##############################################################################

sub normalize_field {
    my ($field, $measure, @data) = @_;

    return 0 if scalar(@data) == 0;
    if(exists($numerical_field{$field})) {
        # Numerical fields have a measure in [0, n], where zero means
        # different and n means all identical, and n is the length of
        # @data
        return $measure / scalar(@data);
    }
    elsif(exists($textual_field{$field})) {
        # For textual fields, the measure is the number of words that
        # are the same (decaying with abstract and title). We take the
        # bigger of the two numbers to work out what the maximum match
        # could be if the textual fields were identical, and return
        # $measure as a fraction of that.

        return 0 if(scalar(@data) == 0);

        if(scalar(@data) == 1) {
            if(!exists($warnings_once{"text$field measure$measure"})) {
                warn "Textual field $field has measure $measure and only one datum ",
                    "${data[0]}; two are expected for all text fields\n";
                $warnings_once{"text$field measure$measure"} = 1;
            }
            return 0;
        }

        my $n_words = $data[0] > $data[1] ? $data[0] : $data[1];
        return 0 if $n_words == 0;

        if($field eq 'abstract') {
            # The denominator used to normalize is the formula for
            # summation of finite geometric series with r < 1 from
            # https://en.wikipedia.org/wiki/Geometric_series
            return ( $measure /
                ((1 - ($abstract_decay ** ($n_words + 1))) / (1 - $abstract_decay))
            );
        }
        elsif($field eq 'title') {
            return ( $measure /
                ((1 - ($title_decay ** ($n_words + 1))) / (1 - $title_decay))
            );
        }
        else {
            return $measure / $n_words;
        }
    }
    else {
        # Authors and editors are counts of number of matching names
        # with higher scores for surname and initials match than
        # surname only match
        my $max_n = shift(@data);
        foreach my $datum (@data) {
            $max_n = $datum if $datum > $max_n;
        }
        return 0 if $max_n == 0;
        return $measure / ($max_n * &BibTeX::surname_and_initials());
    }
}

##############################################################################
#
#   #### #   # ####        #   #  ###  #####  #### #   # #####  ####
#  #     ## ## #   #       ## ## #   #   #   #     #   # #     #    
#  #     # # # ####        # # # #####   #   #     ##### ####   ### 
#  #     #   # #           #   # #   #   #   #     #   # #         #
#   #### #   # #           #   # #   #   #    #### #   # ##### #### 
#                    #####                                          
#
# Compare two matches, returning +/-1 if the comparator should be added (because
# it is better than the baseline (+1) or incomparable to it (-1)) and 0 otherwise
#
# Incomparability is also a matter of whether fields exist -- both comparators
# must have the same field entries to be comparable
###############################################################################

sub cmp_matches {
    my ($comparator, $baseline) = @_;

    my $all_better_or_equal = 1;
    my $comparability;
    foreach my $field (@ck_fields) {
        my $comp = $comparator->{$field};
        my $base = $baseline->{$field};

        if(scalar(@$comp) > 0 && scalar(@$base) > 0) {
            my ($comp_measure, $comp_summary) = &field_summary($field, @$comp);
            my ($base_measure, $base_summary) = &field_summary($field, @$base);

            if($comp_measure == $base_measure && !defined($comparability)) {
                $comparability = 0;
                next;
            }

            if($comp_measure < $base_measure) {
                $all_better_or_equal = 0;
                if(defined($comparability) && $comparability > 0) {
                    # Incomparable because an earlier field was better
                    return -1;
                }
                else {
                    $comparability = -1;
                }
            }
            else {
                if(defined($comparability) && $comparability < 0) {
                    # Incomparable because an earlier field was worse
                    return -1;
                }
                else {
                    $comparability = 1;
                }
            }
        }
        elsif(scalar(@$comp) > 0 || scalar(@$base) > 0) {
            # Different fields: incomparable
            return -1;
        }
    }


    if($comparability == 0) {
        return 0;
    }
    else {
        return $all_better_or_equal;
    }
}

##############################################################################
#
#  #####  ###  ##### #     ####         #### #   # #   # #   #  ###  ####  #   #
#  #       #   #     #     #   #       #     #   # ## ## ## ## #   # #   #  # # 
#  ####    #   ####  #     #   #        ###  #   # # # # # # # ##### ####    #  
#  #       #   #     #     #   #           # #   # #   # #   # #   # #   #   #  
#  #      ###  ##### ##### ####        ####   ###  #   # #   # #   # #   #   #  
#                                #####                                          
#                                                                               
##############################################################################

sub field_summary {
    my ($field, $measure, @data) = @_;

    if(exists($textual_field{$field})) {
        my $context = &int_log2(shift(@data));
        foreach my $n_words (@data) {
            my $c = &int_log2($n_words);
            $context = $c if($c > $context);
        }
        return ($measure, $context);
    }
    elsif(exists($numerical_field{$field})) {
        my $context = scalar(@data);
        return ($measure, $context);
    }
    else {
        my $context = shift(@data);
        foreach my $n_authors (@data) {
            $context = $n_authors if($n_authors > $context);
        }
        return ($measure, $context);
    }
}

##############################################################################
#
#  #####  ###  ##### #     ####        #   #  ###  #####  #### #   #
#  #       #   #     #     #   #       ## ## #   #   #   #     #   #
#  ####    #   ####  #     #   #       # # # #####   #   #     #####
#  #       #   #     #     #   #       #   # #   #   #   #     #   #
#  #      ###  ##### ##### ####        #   # #   #   #    #### #   #
#                                #####                              
#                                                                   
##############################################################################

sub field_match {
    my ($field, $bib1, $bib2) = @_;

    if(exists($textual_field{$field})) {
        return &textual_match($field, $bib1, $bib2);
    }
    elsif(exists($numerical_field{$field})) {
        return &numerical_match($field, $numerical_field{$field}, $bib1, $bib2);
    }
    elsif($field eq 'author') {
        return &author_match($bib1, $bib2);
    }
    elsif($field eq 'editor') {
        return &editor_match($bib1, $bib2);
    }
    else {
        die "BUG! Field \"$field\" not recognized\n";
    }
}

##############################################################################
#
#   ###  #   # ##### #   #  ###  ####        #   #  ###  #####  #### #   #
#  #   # #   #   #   #   # #   # #   #       ## ## #   #   #   #     #   #
#  ##### #   #   #   ##### #   # ####        # # # #####   #   #     #####
#  #   # #   #   #   #   # #   # #   #       #   # #   #   #   #     #   #
#  #   #  ###    #   #   #  ###  #   #       #   # #   #   #    #### #   #
#                                      #####                              
#                                                                         
##############################################################################

sub author_match {
    my ($bib1, $bib2) = @_;

    if(exists($bib1->{'author'}) && exists($bib2->{'author'})) {
        &bk_field('author', 1, $bib1, $bib2);
        my $cmp = &BibTeX::cmp_authors($bib1, $bib2, 1);
        &bk_field('author', 0, $bib1, $bib2);
        return [ $cmp, &BibTeX::n_authors($bib1), &BibTeX::n_authors($bib2) ];
    }
    elsif(exists($bib1->{'author'})) {
        return [ 0, &BibTeX::n_authors($bib1), 0 ];
    }
    elsif(exists($bib2->{'author'})) {
        return [ 0, 0, &BibTeX::n_authors($bib2) ];
    }
    else {
        return [ 0, 0, 0 ];
    }
}

##############################################################################
#
#  ##### ####   ###  #####  ###  ####        #   #  ###  #####  #### #   #
#  #     #   #   #     #   #   # #   #       ## ## #   #   #   #     #   #
#  ####  #   #   #     #   #   # ####        # # # #####   #   #     #####
#  #     #   #   #     #   #   # #   #       #   # #   #   #   #     #   #
#  ##### ####   ###    #    ###  #   #       #   # #   #   #    #### #   #
#                                      #####                              
#                                                                         
##############################################################################

sub editor_match {
    my ($bib1, $bib2) = @_;

    if(exists($bib1->{'editor'}) && exists($bib2->{'editor'})) {
        &bk_field('editor', 1, $bib1, $bib2);
        my $cmp = &BibTeX::cmp_editors($bib1, $bib2, 1);
        &bk_field('editor', 0, $bib1, $bib2);
        return [ $cmp, &BibTeX::n_editors($bib1), &BibTeX::n_editors($bib2) ];
    }
    elsif(exists($bib1->{'editor'})) {
        return [ 0, &BibTeX::n_editors($bib1), 0 ];
    }
    elsif(exists($bib2->{'editor'})) {
        return [ 0, 0, &BibTeX::n_editors($bib2) ];
    }
    else {
        return [ 0, 0, 0 ];
    }
}

################################################################################
#
# ####  #   #       #####  ###  ##### #     #### 
# #   # #  #        #       #   #     #     #   #
# ####  ###         ####    #   ####  #     #   #
# #   # #  #        #       #   #     #     #   #
# ####  #   #       #      ###  ##### ##### #### 
#             #####                              
#                                                
# Allow a field (intended to be 'author' or 'editor') to be backed up
# temporarily ($bk = 1) or restored from backup ($bk = 0) while a computation
# is done on that field with all accents removed.
################################################################################

sub bk_field {
    my ($field, $bk, @papers) = @_;

    my $bk_field = "_bk_".$field;
    foreach my $paper (@papers) {
        if($bk) {
            $paper->{$bk_field} = $paper->{$field};
            $paper->{$field} = &Latin::no_accents($paper->{$field});
        }
        elsif(exists($paper->{$bk_field})) {
            $paper->{$field} = $paper->{$bk_field};
            delete $paper->{$bk_field};
        }
        else {
            die "BUG! Attempt to restore non-backed-up field $field in paper ",
                &paper_info($paper), "\n";
        }
    }
}

##############################################################################
#
#  #   # #   # #   # ##### ####   ###   ####  ###  #           #   #  ###  #####  #### #   #
#  ##  # #   # ## ## #     #   #   #   #     #   # #           ## ## #   #   #   #     #   #
#  # # # #   # # # # ####  ####    #   #     ##### #           # # # #####   #   #     #####
#  #  ## #   # #   # #     #   #   #   #     #   # #           #   # #   #   #   #     #   #
#  #   #  ###  #   # ##### #   #  ###   #### #   # #####       #   # #   #   #    #### #   #
#                                                        #####                              
#                                                                                           
# Return a measure that is larger for smaller differences between pairs of
# numbers in $field of $bib1 and $bib2. $n tells us how many pairs of numbers
# to expect.
# 
#       -1  means if there's a numerical range (separated by a -), then expect
#           two numbers; else expect 1 (e.g. issues can have ranges)
#        1  means expect one number (e.g. year, number); all non-numbers will
#           be removed from the strings
#        2+ means expect two (e.g. page ranges), but accept any non number
#           as a range separator
##############################################################################

sub numerical_match {
    my ($field, $n, $bib1, $bib2) = @_;

    if(exists($bib1->{$field}) && exists($bib2->{$field})) {
        my $entry1 = $bib1->{$field};
        my $entry2 = $bib2->{$field};

        if($n == -1) {
            if($entry1 =~ /^\d+-\d+$/ || $entry2 =~ /^\d+-\d+$/) {
                $n = 2;
            }
            else {
                $n = 1;
            }
        }

        if($n == 1) {
            $entry1 =~ s/\D//g;
            $entry2 =~ s/\D//g;

            if($entry1 eq "" || $entry2 eq "") {
                return [-1, -1] unless($field eq 'number');
                # Handle months as numbers -- this might not be necessary
                if(&cmp_months($bib1->{$field}, $bib2->{$field})) {
                    return [ &diff_measure(0), 0 ];
                }
                else {
                    return [ -1, -1 ];
                }
            }
            else {
                return [ &diff_measure($entry1 - $entry2), abs($entry1 - $entry2) ];
            }
        }
        else {
            my @values1;
            foreach my $value (split(/\D+/, $entry1)) {
                push(@values1, $value) if($value =~ /\d/);
            }
            my @values2;
            foreach my $value (split(/\D+/, $entry2)) {
                push(@values2, $value) if($value =~ /\d/);
            }

            my $ret = [];
            my $diff = 0;
            for(my $i = 0; $i < $n; $i++) {
                if($i <= $#values1 && $i <= $#values2) {
                    $diff += &diff_measure($values1[$i] - $values2[$i]);
                    push(@$ret, abs($values1[$i] - $values2[$i]));
                }
                else {
                    push(@$ret, -1);
                }
            }
            unshift(@$ret, $diff);
            return $ret;
        }
    }
    else {
        my $ret = [-1];
        for(my $i = 1; $i <= abs($n); $i++) {
            push(@$ret, -1);
        }
        return $ret;
    }
}

################################################################################
#
#  #### #   # ####        #   #  ###  #   # ##### #   #  ####
# #     ## ## #   #       ## ## #   # ##  #   #   #   # #    
# #     # # # ####        # # # #   # # # #   #   #####  ### 
# #     #   # #           #   # #   # #  ##   #   #   #     #
#  #### #   # #           #   #  ###  #   #   #   #   # #### 
#                   #####                                    
#                                                            
################################################################################

sub cmp_months {
    my ($value1, $value2) = @_;

    my %months = (
        'JANUARY' => 1, 'JAN' => 1,
        'FEBRUARY'=> 2, 'FEB' => 2, 'FEBUARY' => 2, # 10.1371/journal.pone.0246788
        'MARCH' => 3, 'MAR' => 3,
        'APRIL' => 4, 'APR' => 4,
        'MAY' => 5,
        'JUNE' => 6, 'JUN' => 6,
        'JULY' => 7, 'JUL' => 7,
        'AUGUST' => 8, 'AUG' => 8,
        'SEPTEMBER' => 9, 'SEP' => 9,
        'OCTOBER' => 10, 'OCT' => 10,
        'NOVEMBER' => 11, 'NOV' => 11,
        'DECEMBER' => 12, 'DEC' => 12
    );

    if(exists($months{uc($value1)}) && exists($months{uc($value2)})) {
        return $months{uc($value1)} == $months{uc($value2)};
    }
    else {
        return 0;
    }
}

################################################################################
#
# ####   ###  ##### #####       #   # #####  ###   #### #   # ####  #####
# #   #   #   #     #           ## ## #     #   # #     #   # #   # #    
# #   #   #   ####  ####        # # # ####  #####  ###  #   # ####  #### 
# #   #   #   #     #           #   # #     #   #     # #   # #   # #    
# ####   ###  #     #           #   # ##### #   # ####   ###  #   # #####
#                         #####                                          
#                                                                        
################################################################################

sub diff_measure {
    my ($diff) = @_;

    return exp(-1 * ($diff ** 2));
}

##############################################################################
#
#  ##### ##### #   # ##### #   #  ###  #           #   #  ###  #####  #### #   #
#    #   #      # #    #   #   # #   # #           ## ## #   #   #   #     #   #
#    #   ####    #     #   #   # ##### #           # # # #####   #   #     #####
#    #   #      # #    #   #   # #   # #           #   # #   #   #   #     #   #
#    #   ##### #   #   #    ###  #   # #####       #   # #   #   #    #### #   #
#                                            #####                              
#                                                                               
# For textual fields, the value returned is the number of words that are the
# same in the two fields (with decay if so specified), and then the number
# of words in each of $bib1 and $bib2.
##############################################################################

sub textual_match {
    my ($field, $bib1, $bib2) = @_;

    if(exists($bib1->{$field}) && exists($bib2->{$field})) {
        my $txt1 = lc(&Latin::no_accents($bib1->{$field}));
        $txt1 =~ s/^[a-z0-9 ]+/ /g;
        $txt1 =~ s/\s+/ /g;

        my $txt2 = lc(&Latin::no_accents($bib2->{$field}));
        $txt2 =~ s/^[a-z0-9 ]+/ /g;
        $txt2 =~ s/\s+/ /g;

        return [
            &TextTK::match_words($txt1, $txt2, $textual_field{$field}),
            &TextTK::n_words($bib1->{$field}), &TextTK::n_words($bib2->{$field})
        ];
    }
    elsif(exists($bib1->{$field})) {
        return [ 0, &TextTK::n_words($bib1->{$field}), 0 ];
    }
    elsif(exists($bib2->{$field})) {
        return [ 0, 0, &TextTK::n_words($bib2->{$field}) ];
    }
    else {
        return [ 0, 0, 0 ];
    }

}

##############################################################################
#
#  #   # ##### ####   #### #####       ####   ###   ### 
#  ## ## #     #   # #     #           #   # #   #   #  
#  # # # ####  ####  #  ## ####        #   # #   #   #  
#  #   # #     #   # #   # #           #   # #   #   #  
#  #   # ##### #   #  #### #####       ####   ###   ### 
#                                #####                  
#                                                       
# We are expecting this only to be called once for each paper with a DOI
# with the first paper being Web of Science, and the second Scopus.
##############################################################################

sub merge_doi {
    my ($pap1, $pap2) = @_;

    if(!exists($pap1->{'doi'}) || !exists($pap2->{'doi'})) {
        die "BUG: Attempt to merge DOI with one or other paper ",
            "not having a DOI!\n";
    }
    if($pap1->{'doi'} ne $pap2->{'doi'}) {
        die "BUG: Attempt to merge papers with different DOIs \"",
            $pap1->{'doi'}, "\" and \"", $pap2->{'doi'}, "\"\n";
    }
    foreach my $key (keys(%$pap1), keys(%$pap2)) {
        if($key =~ /^_WoS/ || $key =~ /^_Scopus/) {
            die "BUG: Unexpected repeated merge of paper with DOI \"",
                $pap1->{'doi'}, "\"\n";
        }
    }

    return &merge_no_doi($pap1, $pap2);
}


##############################################################################
#
#  #   # ##### ####   #### #####       #   #  ###        ####   ###   ### 
#  ## ## #     #   # #     #           ##  # #   #       #   # #   #   #  
#  # # # ####  ####  #  ## ####        # # # #   #       #   # #   #   #  
#  #   # #     #   # #   # #           #  ## #   #       #   # #   #   #  
#  #   # ##### #   #  #### #####       #   #  ###        ####   ###   ### 
#                                #####             #####                  
#                                                                         
# This procedure merges two papers that don't have DOIs. It should only be
# called once for any paper with a candidate merge. However, to save code
# duplication, it is also called from &merge_doi(), after checking DOI
# sanity.
##############################################################################

sub merge_no_doi {
    my ($pap1, $pap2) = @_;

    my $db1 = &wos_or_scopus($pap1);
    my $db2 = &wos_or_scopus($pap2);

    my $result = {};

    foreach my $key (keys(%$pap1)) {
        if($key =~ /^_WoS/ || $key =~ /^_Scopus/) {
            die "BUG: Unexpected repeated merge of paper from $db1 ",
                &paper_info($pap1);
        }
        if(exists($pap2->{$key})) {
            if(lc($pap1->{$key}) ne lc($pap2->{$key})) {
                $result->{"_${db1}_$key"} = $pap1->{$key};
                $result->{"_${db2}_$key"} = $pap2->{$key};
            }
            # Strings must be equal; choose one that isn't SHOUTING
            elsif($pap1->{$key} =~ /[a-z]/ && $pap2->{$key} !~ /[a-z]/) {
                $result->{$key} = $pap1->{$key};
            }
            elsif($pap2->{$key} =~ /[a-z]/ && $pap2->{$key} !~ /[a-z]/) {
                $result->{$key} = $pap2->{$key};
            }
            else {
                # Strings must be equal including case
                $result->{$key} = $pap1->{$key};
            }
        }
        else {
            # $pap2 doesn't have the key
            $result->{$key} = $pap1->{$key};
        }
    }
    # Add data from fields in $pap2 that $pap1 doesn't have
    foreach my $key (keys(%$pap2)) {
        if($key =~ /^_WoS/ || $key =~ /^_Scopus/) {
            die "BUG: Unexpected repeated merge of paper from $db2 ";
        }

        if(!exists($pap1->{$key})) {
            $result->{$key} = $pap2->{$key};
        }
    }

    return $result;
}

##############################################################################
#
#  ####   ###  ####  ##### ####         ###  #   # #####  ### 
#  #   # #   # #   # #     #   #         #   ##  # #     #   #
#  ####  ##### ####  ####  ####          #   # # # ####  #   #
#  #     #   # #     #     #   #         #   #  ## #     #   #
#  #     #   # #     ##### #   #        ###  #   # #      ### 
#                                #####                        
#                                                             
# Return a string summarizing enough information that it should be possible
# to find a paper in the source files.
##############################################################################

sub paper_info {
    my ($paper) = @_;

    my $str = "";
    if(exists($paper->{'_filename'})) {
        $str .= "file \"".($paper->{'_filename'})."\"";
        if(exists($paper->{'_line'})) {
            $str .= ", line ".($paper->{'_line'});
        }
    }
    elsif(exists($paper->{'_WoS_filename'}) && exists($paper->{'_Scopus_filename'})) {
        $str .= "WoS file \"".($paper->{'_WoS_filename'})."\"";
        if(exists($paper->{'_WoS_line'})) {
            $str .= ", line ".($paper->{'_WoS_line'});
        }
        elsif(exists($paper->{'_line'})) {
            # It is _possible_ that the line numbers in the WoS and Scopus
            # file happen to be the same
            $str .= ", line ".($paper->{'_line'});
        }
        $str .= "; Scopus file \"".($paper->{'_Scopus_filename'})."\"";
        if(exists($paper->{'_Scopus_line'})) {
            $str .= ", line ".($paper->{'_Scopus_line'});
        }
        elsif(exists($paper->{'_line'})) {
            $str .= ", line ".($paper->{'_line'});
        }
    }
    if(exists($paper->{'_bibkey'})) {
        $str .= "; " if length($str) > 0;
        $str .= "cite key \"".($paper->{'_bibkey'})."\"";
    }
    elsif(exists($paper->{'_WoS_bibkey'}) && exists($paper->{'_Scopus_bibkey'})) {
        $str .= "; " if length($str) > 0;
        $str .= "WoS cite key \"".($paper->{'_WoS_bibkey'})."\"";
        $str .= "; Scopus cite key \"".($paper->{'_Scopus_bibkey'})."\"";
    }
    if(exists($paper->{'title'})) {
        $str .= "; " if length($str) > 0;
        $str .= "entitled \"".($paper->{'title'})."\"";
    }
    elsif(exists($paper->{'_WoS_title'}) && exists($paper->{'_Scopus_title'})) {
        $str .= "; " if length($str) > 0;
        $str .= "WoS title \"".($paper->{'_WoS_title'})."\"";
        $str .= "; Scopus title \"".($paper->{'_Scopus_title'})."\"";
    }
    if(length($str) == 0) {
        foreach my $key (keys(%$paper)) {
            $str .= "; " if length($str) > 0;
            $str .= "\"$key\" = \"".($paper->{$key})."\"";
        }
    }
    if(length($str) == 0) {
        $str = "(no information)";
    }
    return $str;
}

##############################################################################
#
#   #### ##### #####       ####   ###  ####  #   # ##### #   #
#  #     #       #         #   #   #   #   # #  #  #      # # 
#  #  ## ####    #         ####    #   ####  ###   ####    #  
#  #   # #       #         #   #   #   #   # #  #  #       #  
#   #### #####   #         ####   ###  ####  #   # #####   #  
#                    #####                                    
#                                                             
##############################################################################

sub get_bibkey {
    my ($paper) = @_;

    my $key = "";

    if(exists($paper->{'author'})) {
        my @surnames = &BibTeX::author_surnames($paper);
        
        if(scalar(@surnames) <= $n_author_citekey) {
            $key .= join("_", @surnames);
        }
        else {
            $key .= $surnames[0]."_et_al";
        }
    }
    else {
        $key .= "Anonymous";
    }

    if(exists($paper->{'year'})) {
        $key .= "_".$paper->{'year'};
    }
    else {
        $key .= "_no_date";
    }

    if(exists($paper->{'title'})) {
        my @words = split(" ", lc($paper->{'title'}));
        for(my $i = 1; $i <= $n_title_citekey && scalar(@words) > 0; $i++) {
            $key .= "_".(shift(@words));
        }
    }
    else {
        $key .= "_Untitled";
    }

    $key =~ s/\W+/_/g;
    my $n = 0;
    my $key_n = $key;
    while(exists($used_keys{lc($key_n)})) {
        $n++;
        $key_n = "${key}_$n";
    }
    $key = $key_n if $n > 0;

    $used_keys{lc($key)} = 1;

    return $key;
}

##############################################################################
#
#   ####  ###  #   # #####       ####   ###  #### 
#  #     #   # #   # #           #   #   #   #   #
#   ###  ##### #   # ####        ####    #   #### 
#      # #   #  # #  #           #   #   #   #   #
#  ####  #   #   #   #####       ####   ###  #### 
#                          #####                  
#                                                 
##############################################################################

sub save_bib {
    my ($db, $filename) = @_;

    my $bib;
    open($bib, ">:encoding(UTF-8)", $filename) or die "Cannot create bib file $filename: $!\n";

    foreach my $paper (@$db) {
        &save_paper($bib, $paper);
    }

    close($bib);
}

##############################################################################
#
#   ####  ###  #   # #####       ####   ###  ####  ##### #### 
#  #     #   # #   # #           #   # #   # #   # #     #   #
#   ###  ##### #   # ####        ####  ##### ####  ####  #### 
#      # #   #  # #  #           #     #   # #     #     #   #
#  ####  #   #   #   #####       #     #   # #     ##### #   #
#                          #####                              
#                                                             
##############################################################################

sub save_paper {
    my ($fp, $paper) = @_;

    if(exists($paper->{'_bibtype'})) {
        print $fp "\@".($paper->{'_bibtype'})."{";
    }
    else {
        print $fp "\@unknown{";
    }

    print $fp &get_bibkey($paper), ",\n";

    foreach my $key (sort {$a cmp $b} keys(%$paper)) {
        print $fp "  $key = \{", $paper->{$key}, "\},\n";
    }

    print $fp "}\n\n";
}

##############################################################################
# wos_or_scopus
#
#  #   #  ###   ####        ###  ####         ####  ####  ###  ####  #   #  ####
#  #   # #   # #           #   # #   #       #     #     #   # #   # #   # #    
#  # # # #   #  ###        #   # ####         ###  #     #   # ####  #   #  ### 
#  # # # #   #     #       #   # #   #           # #     #   # #     #   #     #
#   # #   ###  ####         ###  #   #       ####   ####  ###  #      ###  #### 
#                    #####             #####                                    
#                                                                               
# Test whether a BibTeX entry is from the Web of Science or Scopus downloads.
# All Web of Science entries have a 'unique-id' key. All Scopus entries have
# a 'source' key set to 'Scopus'.
#
# Returns 'WoS' for Web of Science; 'Scopus' for Scopus, and 'NA' if neither
# condition is fulfilled
##############################################################################

sub wos_or_scopus {
    my ($bib) = @_;

    my $wos = exists($bib->{'unique-id'});
    my $scopus = (exists($bib->{'source'}) && $bib->{'source'} eq 'Scopus');

    if($wos && $scopus) {
        return "Both";
    }
    elsif($wos) {
        return "WoS";
    }
    elsif($scopus) {
        return "Scopus";
    }
    else {
        $wos = (exists($bib->{'_filename'}) && $bib->{'_filename'} =~ /\/wos\//);
        $scopus = (exists($bib->{'_filename'}) && $bib->{'_filename'} =~ /\/scopus\//);
        my $woswos = exists($bib->{'_WoS_filename'});
        my $scopusscopus = exists($bib->{'_Scopus_filename'});
        if($woswos && $scopusscopus) {
            return "Both";
        }
        elsif($wos) {
            return "WoS";
        }
        elsif($scopus) {
            return "Scopus";
        }
        else {
            return "NA";
        }
    }

}

##############################################################################
#
#   #### #   #  ###   ###   #### #####       #   # ##### ####   #### ##### #### 
#  #     #   # #   # #   # #     #           ## ## #     #   # #     #     #   #
#  #     ##### #   # #   #  ###  ####        # # # ####  ####  #  ## ####  #   #
#  #     #   # #   # #   #     # #           #   # #     #   # #   # #     #   #
#   #### #   #  ###   ###  ####  #####       #   # ##### #   #  #### ##### #### 
#                                      #####                                    
#                                                                               
# For papers that have been merged, we need to choose one of the WoS or
# Scopus options. The rules for this:
#
# (a) Text fields: choose the one with accents; if neither have accents,
#     choose the longer field
# (b) Numerical fields: choose the one with more digits; if those are the
#     same, choose the one with fewer non-digits.
#
# If the rules don't allow a choice, choose the Web of Science one, on the
# potentially biased and somewhat random impression I have formed that this
# is the more accurate database of the two.
##############################################################################

sub choose_merged {
    my ($db) = @_;

    foreach my $paper (@$db) {
        my %merged_fields;

        foreach my $field (keys(%$paper)) {
            if($field =~ /^_(WoS|Scopus)_(.+)$/) {
                my ($which, $field_name) = ($1, $2);

                $merged_fields{$field_name}->{$which} = $paper->{$field};
            }
        }

        next if (scalar(keys(%merged_fields)) == 0);

        foreach my $field (keys(%merged_fields)) {
            if(exists($paper->{$field})) {
                warn "BUG: Merged field $field (", $paper->{$field}, 
                    ") exists in paper ", &paper_info($paper),
                    " (and will be overwritten)\n";
            }
        }

        foreach my $field (keys(%merged_fields)) {
            if(!exists($merged_fields{$field}->{'WoS'})) {
                warn "BUG: Scopus but no WoS entry for $field in merged paper ",
                    &paper_info($paper), "\n";
                $paper->{$field} = $merged_fields{$field}->{'Scopus'};
            }
            elsif(!exists($merged_fields{$field}->{'Scopus'})) {
                warn "BUG: WoS but no Scopus entry for $field in merged paper ",
                    &paper_info($paper), "\n";
                $paper->{$field} = $merged_fields{$field}->{'WoS'};
            }
            else {
                my $str_wos
                    = &Latin::decode_latex($merged_fields{$field}->{'WoS'});
                my $str_scopus
                    = &Latin::decode_latex($merged_fields{$field}->{'Scopus'});

                if(exists($textual_field{$field})
                    || $field eq 'author' || $field eq 'editor'
                ) {
                    if(&Latin::has_accent($str_wos)
                        && !&Latin::has_accent($str_scopus)
                    ) {
                        $paper->{$field} = $merged_fields{$field}->{'WoS'};
                    }
                    elsif(&Latin::has_accent($str_scopus)
                        && !&Latin::has_accent($str_wos)
                    ) {
                        $paper->{$field} = $merged_fields{$field}->{'Scopus'};
                    }
                    elsif(length($str_wos) > length($str_scopus)) {
                        $paper->{$field} = $merged_fields{$field}->{'WoS'};
                    }
                    elsif(length($str_scopus) > length($str_wos)) {
                        $paper->{$field} = $merged_fields{$field}->{'Scopus'};
                    }
                    else {
                        $paper->{$field} = $merged_fields{$field}->{'WoS'};
                    }
                }
                elsif(exists($numerical_field{$field})) {
                    my ($wos_dig, $scopus_dig) = ($str_wos, $str_scopus);
                    my ($wos_nodig, $scopus_nodig) = ($str_wos, $str_scopus);

                    $wos_dig =~ s/\D//g;
                    $wos_nodig =~ s/\d//g;
                    $scopus_dig =~ s/\D//g;
                    $scopus_nodig =~ s/\D//g;

                    if(length($wos_dig) > length($scopus_dig)) {
                        $paper->{$field} = $merged_fields{$field}->{'WoS'};
                    }
                    elsif(length($scopus_dig) > length($wos_dig)) {
                        $paper->{$field} = $merged_fields{$field}->{'Scopus'};
                    }
                    elsif(length($wos_nodig) < length($scopus_nodig)) {
                        $paper->{$field} = $merged_fields{$field}->{'WoS'};
                    }
                    elsif(length($scopus_nodig) < length($wos_nodig)) {
                        $paper->{$field} = $merged_fields{$field}->{'Scopus'};
                    }
                    else {
                        $paper->{$field} = $merged_fields{$field}->{'WoS'};
                    }
                }
                else {
                    $paper->{$field} = $merged_fields{$field}->{'WoS'};
                }
            }
        }
    }
}

##############################################################################
#
#  ####  ##### ####   ###  ####  #####       #####  ###  ####  #     #####  ####
#  #   # #     #   # #   # #   #   #           #   #   # #   # #     #     #    
#  ####  ####  ####  #   # ####    #           #   ##### ####  #     ####   ### 
#  #   # #     #     #   # #   #   #           #   #   # #   # #     #         #
#  #   # ##### #      ###  #   #   #           #   #   # ####  ##### ##### #### 
#                                      #####                                    
#                                                                               
##############################################################################

sub report_tables {
    my ($filename) = @_;

    my $fp;
    open($fp, ">", $filename) || die "Cannot create report in file $filename: $!\n";

    &report_read_merge($fp);
    &report_field_thresholds($fp);

    close($fp);
}

##############################################################################
#
#  ####  ##### ####   ###  ####  #####       ####  #####  ###  #### 
#  #   # #     #   # #   # #   #   #         #   # #     #   # #   #
#  ####  ####  ####  #   # ####    #         ####  ####  ##### #   #
#  #   # #     #     #   # #   #   #         #   # #     #   # #   #
#  #   # ##### #      ###  #   #   #         #   # ##### #   # #### 
#                                      #####                        
#                                                                   
#        #   # ##### ####   #### #####
#        ## ## #     #   # #     #    
#        # # # ####  ####  #  ## #### 
#        #   # #     #   # #   # #    
#        #   # ##### #   #  #### #####
#  #####                              
#                                     
##############################################################################

sub report_read_merge {
    my ($fp) = @_;

    my %row_txt = (
        'doi' => 'Download; has DOI',
        'n' => 'Downloaded',
        'unique' => 'Identified as unique',
        'u-doi' => 'Unique with a DOI',
        'dodgy' => 'Non-unique DOIs',
        'no' => 'Unique with no DOI',
        'unmerged-doi' => 'DOI not in other DB',
        'unmerged-no-doi' => 'No DOI; not matched in other DB',
    );

    my @row_order = ('n', 'doi', 'unique', 'u-doi', 'no', 'dodgy', 'unmerged-doi',
        'unmerged-no-doi');

    print $fp "\\begin{table}[!t]\n    \\begin{tabular}{p{5cm}|r r}\n";
    print $fp "        \\toprule\n         & Web of Science & Scopus \\\\\n";
    print $fp "        \\midrule\n";
    foreach my $row (@row_order) {
        print $fp "        $row_txt{$row} & ";
        if(exists($data{'WoS'}->{$row})) {
            print $fp $data{'WoS'}->{$row};
        }
        else {
            print $fp "--";
        }
        print $fp " & ";
        if(exists($data{'Scopus'}->{$row})) {
            print $fp $data{'Scopus'}->{$row};
        }
        else {
            print $fp "--";
        }
        print $fp " \\\\\n";
    }
    print $fp "        \\bottomrule\n    \\end{tabular}\n";
    print $fp "    \\caption{Summary of results from download and merge",
        " of data from Web of Science and Scopus, leading to ",
        scalar(@db), " unique records overall.}\n";
    print $fp "    \\label{tab:merge-summary}\n";
    print $fp "\\end{table}\n\n";
}

##############################################################################
#
#  ####  ##### ####   ###  ####  #####       #####  ###  ##### #     #### 
#  #   # #     #   # #   # #   #   #         #       #   #     #     #   #
#  ####  ####  ####  #   # ####    #         ####    #   ####  #     #   #
#  #   # #     #     #   # #   #   #         #       #   #     #     #   #
#  #   # ##### #      ###  #   #   #         #      ###  ##### ##### #### 
#                                      #####                              
#                                                                         
#        ##### #   # ####  #####  #### #   #  ###  #     ####   ####
#          #   #   # #   # #     #     #   # #   # #     #   # #    
#          #   ##### ####  ####   ###  ##### #   # #     #   #  ### 
#          #   #   # #   # #         # #   # #   # #     #   #     #
#          #   #   # #   # ##### ####  #   #  ###  ##### ####  #### 
#  #####                                                            
#                                                                   
##############################################################################

sub report_field_thresholds {
    my ($fp) = @_;

    print $fp "\\begin{table}[!t]\n    \\begin{tabular}{l|r|r}\n";
    print $fp "        \\toprule\n        Field & Weight & Threshold \\\\\n";
    print $fp "        \\midrule\n";
    foreach my $row (sort {$a cmp $b} @ck_fields) {
        print $fp "       $row & ";
        if(exists($weight_field{$row})) {
            print $fp $weight_field{$row};
        }
        else {
            print $fp "--";
        }
        print $fp " & ";
        if(exists($field_threshold{$row})) {
            my @summaries = keys(%{$field_threshold{$row}});
            if(scalar(@summaries) == 0) {
                print $fp "--";
            }
            else {
                my $min = $field_threshold{$row}->{shift @summaries};
                foreach my $summary (@summaries) {
                    my $measure = $field_threshold{$row}->{$summary};
                    $min = $measure if $measure < $min;
                }
                if($min >= 0) {
                    print $fp $min;
                } 
                else {
                    print $fp "--";
                }
            }
        }
        elsif($row eq 'year') {
            print $fp "(\$|y_1 - y_2| \\leq $max_year_diff\$)";
        }
        else {
            print $fp "--";
        }
        print $fp " \\\\\n";
    }
    print $fp "        \\bottomrule\n    \\end{tabular}\n";
    print $fp "    \\caption{Summary of weights and thresholds for DOI-matched ",
        "entries across Scopus and Web of Science, for each ",
        "important bibliographic field.}\n";
    print $fp "    \\label{tab:merge-thresholds}\n";
    print $fp "\\end{table}\n\n";
}

##############################################################################
#
#  #   #  ###  #####  #### #   #        ####  ####  ###  ####  #   #  ####
#  ## ## #   #   #   #     #   #       #     #     #   # #   # #   # #    
#  # # # #####   #   #     #####        ###  #     #   # ####  #   #  ### 
#  #   # #   #   #   #     #   #           # #     #   # #     #   #     #
#  #   # #   #   #    #### #   #       ####   ####  ###  #      ###  #### 
#                                #####                                    
#                                                                         
# Parallelize the search per scopus paper
##############################################################################

sub match_scopus {
    my ($fp, $maxproc, $maxmem, $children, $exitstatus, $sc_ix, $sc_paper,
        $sc_match, $wos_match, $wos_db, $wos_years, $field_threshold) = @_;

    my @pids = &wait_for($fp, $maxproc, $maxmem, $children, $exitstatus,
        $wos_match, $sc_match, $field_threshold);
    FORK: {
        # Try to avoid fork failure through out of memory
        my ($size, $peak, $free) = &mem_info();
        while($size ne "NA" && $free ne "NA" && $size > $free) {
            sleep 1;
            ($size, $peak, $free) = &mem_info();
        }
        my $dt = &iso_date();
        my $pid;

        if($pid = fork()) {       # parent
            $children->{$pid} = "/var/tmp/SLR-$dt-$pid.csv";
            return @pids;
        }
        elsif(defined($pid)) {    # child
            &match_wos($sc_ix, $sc_paper, "/var/tmp/SLR-$dt-$$.csv", $wos_db,
                $wos_years, $field_threshold);
            exit 0;
        }
        elsif($!{EAGAIN}) {
            sleep 5;
            redo FORK;
        }
        elsif($redo_count < $fork_err_redo_max) {
            sleep 60;
            $redo_count++;
            redo FORK;
        }
        else {
            die "Fork error redo count failed $redo_count times. Latest error: $!\n";
        }
    }
}

##############################################################################
#
#  #   #  ###   ###  #####       #####  ###  #### 
#  #   # #   #   #     #         #     #   # #   #
#  # # # #####   #     #         ####  #   # #### 
#  # # # #   #   #     #         #     #   # #   #
#   # #  #   #  ###    #         #      ###  #   #
#                          #####                  
#                                                 
##############################################################################

sub wait_for {
    my ($fp, $max_nchildren, $max_mem, $children, $exitstatus, $wos_match, $sc_match, $thresholds) = @_;
    
    my @pids;
    my ($size) = &mem_info();
    my $n = scalar(keys(%$children));
    while($n >= $max_nchildren && ($size * $n) >= $max_mem) {
        my $pid = wait();

        if($pid != -1 && exists($children->{$pid})) {
            $exitstatus->{$pid} = $?;
            if(($exitstatus->{$pid} & 0xFF) == 0) {
                &read_match($fp, $pid, $children->{$pid}, $wos_match, $sc_match, $thresholds);
            }
            else {
                warn "Run $pid stopped with non-zero exit status ",
                    $exitstatus->{$pid}, " -- data file \"",
                    $children->{$pid}, "\" not deleted\n";
            }
            delete $children->{$pid};
        }
        elsif($pid == -1) {
            die "Expecting ", scalar(keys(%$children)), " child processes, but ",
                "there don't seem to be any\n";
        }
        elsif(!exists($children->{$pid})) {
            warn "Child process $pid is not one I knew about!\n";
        }

        push(@pids, $pid);
        ($size) = &mem_info();
        $n = scalar(keys(%$children));
    }
    return @pids;
}

##############################################################################
#
#  #   #  ###  #####  #### #   #       #   #  ###   ####
#  ## ## #   #   #   #     #   #       #   # #   # #    
#  # # # #####   #   #     #####       # # # #   #  ### 
#  #   # #   #   #   #     #   #       # # # #   #     #
#  #   # #   #   #    #### #   #        # #   ###  #### 
#                                #####                  
#                                                       
##############################################################################

sub match_wos {
    my ($sc_ix, $sc_paper, $filename, $wos_db, $wos_years, $field_threshold) = @_;
    my $i_wos = 0;
    my $t_6 = times();

    my %wos_match;
    my %sc_match;

    foreach my $wos_ix (@{$wos_years->{$sc_paper->{'year'}}}) {
        # Populate %wos_match and %sc_match
        my $wos_paper = $wos_db->[$wos_ix];

        if(&title_ok($wos_paper, $sc_paper, $field_threshold)) {
            $i_wos++;

            my $merge_result = &merge_test($wos_paper, $sc_paper);
            if(exists($wos_match{$wos_ix})) {
                if(&pareto($wos_match{$wos_ix}, $merge_result)) {
                    $wos_match{$wos_ix}->{$sc_ix} = $merge_result;
                }
            }
            else {
                $wos_match{$wos_ix}->{$sc_ix} = $merge_result;
            }
            if(exists($sc_match{$sc_ix})) {
                if(&pareto($sc_match{$sc_ix}, $merge_result)) {
                    $sc_match{$sc_ix}->{$wos_ix} = $merge_result;
                }
            }
            else {
                $sc_match{$sc_ix}->{$wos_ix} = $merge_result;
            }
        }
    }

    my $t7 = times() - $t_6;
    my ($size, $peak, $free, $avail) = &mem_info();

    open(FP, ">", $filename)
        or die "Cannot create temporary match file \"$filename\": $!\n";
    foreach my $wix (sort {$a <=> $b} keys(%wos_match)) {
        foreach my $six (sort {$a <=> $b} keys(%{$wos_match{$wix}})) {
            foreach my $fld (sort {$a cmp $b} keys(%{$wos_match{$wix}->{$six}})) {
                print FP "WoS,$wix,$six,$fld,",
                    join(",", @{$wos_match{$wix}->{$six}->{$fld}}), "\n";
            }
        }
    }
    foreach my $six (sort {$a <=> $b} keys(%sc_match)) {
        foreach my $wix (sort {$a <=> $b} keys(%{$sc_match{$six}})) {
            foreach my $fld (sort {$a cmp $b} keys(%{$sc_match{$six}->{$wix}})) {
                print FP "Scopus,$six,$wix,$fld,",
                    join(",", @{$sc_match{$six}->{$wix}->{$fld}}), "\n";
            }
        }
    }
    print FP "Time,$i_wos,$t7\n";
    print FP "Memory,$size,$peak,$free,$avail\n";
    close(FP);
}

##############################################################################
#
#  ###   ####  #### ##### ####  #####       #   #  ###  #####  #### #   #
# #   # #     #     #     #   #   #         ## ## #   #   #   #     #   #
# ##### #     #     ####  ####    #         # # # #####   #   #     #####
# #   # #     #     #     #       #         #   # #   #   #   #     #   #
# #   #  ####  #### ##### #       #         #   # #   #   #    #### #   #
#                                     #####                              
#                                                                        
##############################################################################

sub accept_match {
    my ($matches, $thresholds) = @_;
    my $add = 1;
    my $cmp = 0;

    FIELD: foreach my $field (@ck_fields) {
        my @result = @{$matches->{$field}};

        next FIELD if(scalar(@result) == 0);
        
        my ($measure, $summary) = &field_summary($field, @result);

        $add *= &meets_threshold($field, $summary, $measure, $thresholds);
        $cmp++;

        last FIELD if $add == 0;
    }

    return ($add, $cmp);
}

##############################################################################
#
#  ####  #####  ###  ####        #   #  ###  #####  #### #   #
#  #   # #     #   # #   #       ## ## #   #   #   #     #   #
#  ####  ####  ##### #   #       # # # #####   #   #     #####
#  #   # #     #   # #   #       #   # #   #   #   #     #   #
#  #   # ##### #   # ####        #   # #   #   #    #### #   #
#                          #####                              
#                                                             
##############################################################################

sub read_match {
    my ($fp, $pid, $filename, $wos_match, $sc_match, $thresholds) = @_;

    open(FP, "<", $filename)
        or die "Cannot read temporary match file \"$filename\": $!\n";

    my %matches;
    my ($a, $f, $n, $p, $s, $t);
    while(my $line = <FP>) {
        $line =~ s/\s+$//;

        my ($item, @cells) = split(/,/, $line);

        if($item eq 'WoS') {
            my ($wix, $six, $fld, @data) = @cells;
            $matches{$six}->{$wix}->{$fld} = \@data;
        }
        elsif($item eq 'Scopus') {
            my ($six, $wix, $fld, @data) = @cells;
            $matches{$six}->{$wix}->{$fld} = \@data;
        }
        elsif($item eq 'Time') {
            ($n, $t) = @cells;
        }
        elsif($item eq 'Memory') {
            ($s, $p, $f, $a) = @cells;
            $s = sprintf("%.0f", $s / 1000) if($s ne "NA");
            $p = sprintf("%.0f", $p / 1000) if($p ne "NA");
            $f = sprintf("%.0f", $f / 1000) if($f ne "NA");
            $a = sprintf("%.0f", $a / 1000) if($a ne "NA");
        }
        else {
            die "Unrecognized item \"$item\" in temporary match file \"$filename\"\n";
        }
    }
    close(FP);
    my $n_wix = 0;
    my $n_six = 0;
    my $n_accept = 0;
    my $n_fields = 0;
    my $n_accept_fields = 0;
    foreach my $six (keys(%matches)) {
        $n_six++;
        foreach my $wix (keys(%{$matches{$six}})) {
            $n_wix++;
            my ($yes, $n_cmp) = &accept_match($matches{$six}->{$wix}, $thresholds);
            $n_fields += $n_cmp;
            if($yes) {
                $sc_match->{$six}->{$wix} = $matches{$six}->{$wix};
                $wos_match->{$wix}->{$six} = $matches{$six}->{$wix};
                $n_accept++;
                $n_accept_fields += $n_cmp;
            }
        }
    }
    print $fp "$pid,NA,$n,$t,$s,$p,$f,$a,$n_six,$n_wix,$n_accept,$n_fields,$n_accept_fields\n";
    if(!unlink($filename)) {
        die "Could not delete temporary match file \"$filename\": $!\n";
    }
}

##############################################################################
#
#  #   # ##### #   #       #   #  #### #####
#  ## ## #     ## ##       #   # #     #    
#  # # # ####  # # #       #   #  ###  #### 
#  #   # #     #   #       #   #     # #    
#  #   # ##### #   #        ###  ####  #####
#                    #####                  
#                                           
##############################################################################

sub mem_use {
    my $proc_file = "/proc/$$/status";

    my ($size, $peak) = &mem_info();

    $peak = sprintf("%.0f Mb", $peak / 1000) if($peak ne "NA");
    $size = sprintf("%.0f Mb", $size / 1000) if($size ne "NA");

    return "$size ($peak)";
}

##############################################################################
#
#  #   # ##### #   #        ###  #   # #####  ### 
#  ## ## #     ## ##         #   ##  # #     #   #
#  # # # ####  # # #         #   # # # ####  #   #
#  #   # #     #   #         #   #  ## #     #   #
#  #   # ##### #   #        ###  #   # #      ### 
#                    #####                        
#                                                 
##############################################################################

sub mem_info {
    my $proc_file = "/proc/$$/status";

    my $peak = "NA";
    my $size = "NA";
    my $avail = "NA";
    my $free = "NA";

    if(-e "$proc_file") {
        if(open(STAT, "<", $proc_file)) {
            while(my $line = <STAT>) {
                $line =~ s/\s+$//;

                if($line =~ /^VmPeak:\s+(\d+)\s+kB$/) {
                    $peak = $1;
                }
                elsif($line =~ /^VmSize:\s+(\d+)\s+kB$/) {
                    $size = $1;
                }
            }
            close(STAT);
        }
    }
    if(-e "/proc/meminfo") {
        if(open(PROC, "<", "/proc/meminfo")) {
            while(my $line = <PROC>) {
                $line =~ s/\s+$//;

                if($line =~ /^MemAvailable:\s+(\d+)\s+kB$/) {
                    $avail = $1;
                }
                elsif($line =~ /^MemFree:\s+(\d+)\s+kB$/) {
                    $free = $1;
                }
            }
            close(PROC);
        }
    }
    return ($size, $peak, $free, $avail);
}