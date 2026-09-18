package BibTeX;

use Exporter;

my %last_read_issues;
my $surname_eq = 1;
my $surname_initials_eq = 3;

@ISA = (Exporter);
@EXPORT = qw(read_bib, author_list, editor_list, n_authors, n_editors,
    author_surnames, editor_surnames, author_initials, editor_initials,
    clean_authors, clean_editors, cmp_authors, cmp_editors, tc_author, debibtex_doi,
    n_space_in_key, n_dup_bibkeys, n_null_entries, n_null_entry_articles,
    surname_only, surname_and_initials, set_surname_only, set_surname_and_initials);

use strict;
use warnings;

sub n_space_in_key {
    return $last_read_issues{'articles with space in bibkey'};
}

sub n_dup_bibkeys {
    return $last_read_issues{'duplicated bibkeys'};
}

sub n_null_entries {
    return $last_read_issues{'null entries'};
}

sub n_null_entry_articles {
    return $last_read_issues{'articles with null entries'};
}

sub surname_only {
    return $surname_eq;
}

sub surname_and_initials {
    return $surname_initials_eq;
}

sub set_surname_only {
    my ($value) = @_;
    my $old = $surname_eq;
    $surname_eq = $value;
    return $old;
}

sub set_surname_and_initials {
    my ($value) = @_;
    my $old = $surname_initials_eq;
    $surname_initials_eq = $value;
    return $old;
}

##############################################################################
# read_bib (filename)
#
#  ####  #####  ###  ####        ####   ###  #### 
#  #   # #     #   # #   #       #   #   #   #   #
#  ####  ####  ##### #   #       ####    #   #### 
#  #   # #     #   # #   #       #   #   #   #   #
#  #   # ##### #   # ####        ####   ###  #### 
#                          #####                  
#                                                 
# Read in a BibTeX file with the given name, and return the list of entries
# as read. 
##############################################################################

sub read_bib {
    my ($filename) = @_;

    if(lc($filename) !~ /\.bib$/) {
        warn "Supposed BibTeX file $filename does not have a '.bib' suffix\n";
    }

    open(BIB, "<:encoding(UTF-8)", $filename) or die "BibTeX file $filename could not be opened: $!\n";

    foreach my $key (keys(%last_read_issues)) {
        delete $last_read_issues{$key};
    }

    my @articles;
    my $prev_line;
    my $msg = "NA";
    my %keys;
    my $line_no = 0;
    while(my $line = <BIB>) {
        $line_no++;
        $line =~ s/\s+$//;
        if($line =~ /^\}?\@([A-z]+)\s*\{\s*(.+),$/) {
            my ($type, $key) = ($1, $2);
            $key =~ s/\s+$//;
            $last_read_issues{'articles with space in bibkey'}++ if($key =~ /\s/);
            $last_read_issues{'duplicated bibkeys'}++ if(exists $keys{$key});
            $keys{$key}++;
            my %data;
            $data{'_bibkey'} = $key;
            $data{'_bibtype'} = lc($type);
            $data{'_filename'} = $filename;
            $data{'_line'} = $line_no;

            DATA_LOOP: while($line = <BIB>) {
                $line_no++;
                $line =~ s/\s+$//;
                if($line =~ /^\s*(\S+)\s*=\s*\{([^{]*)\},$/) {
                    my ($entry, $value) = ($1, $2);
                    if(defined($value)) {
                        $data{lc($entry)} = $value;
                    }
                    else {
                        warn "Didn't get any value for entry $entry on line $line",
                            " in article $key in $filename, line $line_no\n";
                    }
                }
                elsif($line =~ /^\s*(\S+)\s*=\s*"(.*)",$/) {
                    my ($entry, $value) = ($1, $2);
                    if(defined($value)) {
                        $data{lc($entry)} = $value;
                    }
                    else {
                        warn "Didn't get any value for entry $entry on line $line",
                            " in article $key in $filename, line $line_no\n";
                    }
                }
                elsif($line =~ /^\s*(\S+)\s*=\s*\{([^{]*)\}$/) {
                    my ($entry, $value) = ($1, $2);
                    if(defined($value)) {
                        $data{lc($entry)} = $value;
                    }
                    else {
                        warn "Didn't get any value for entry $entry on line $line",
                            " in article $key in $filename, line $line_no\n";
                    }
                    last DATA_LOOP;
                }
                elsif($line =~ /^\s*(\S+)\s*=\s*"(.*)"$/) {
                    my ($entry, $value) = ($1, $2);
                    if(defined($value)) {
                        $data{lc($entry)} = $value;
                    }
                    else {
                        warn "Didn't get any value for entry $entry on line $line",
                            " in article $key in $filename, line $line_no\n";
                    }
                    last DATA_LOOP;
                }
                elsif($line =~ /^\s*(\S+)\s*=\s*\{(.*)$/) {
                    my $var = lc($1);
                    my $str = $2;
                    my $open_brackets = &count_chrs('{', $str, '\\') + 1; # Extra is for { in match
                    my $close_brackets = &count_chrs('}', $str, '\\');
                    my $bracket_balance = $open_brackets - $close_brackets;

                    $msg = "\$str = $str; \$bracket_balance = $bracket_balance";
                    $prev_line = $line;
                    MULTI_LINE_LOOP: while($line !~ /\},$/ || $bracket_balance > 0) {
                        if($line = <BIB>) {
                            $line_no++;
                            $line =~ s/^\s+//;
                            $line =~ s/\s+$//;
                            $bracket_balance += &count_chrs('{', $line, '\\')
                                - &count_chrs('}', $line, '\\');
                            $str .= " $line";
                            $msg = "\$str = $str; \$bracket_balance = $bracket_balance";
                            $prev_line = $line;
                        }
                        else {
                            # Should not get here really as it means we didn't find the end
                            # of the field
                            warn "End of field $var not found in record $key of ",
                                "file $filename, line $line_no\n";
                            last MULTI_LINE_LOOP;
                        }
                    }
                    $str = substr($str, 0, -2);
                    if(!defined($str)) {
                        warn "Didn't get any value for many-bracketed key $var in ",
                            "record $key of file $filename, line $line_no\n";
                    }
                    $data{$var} = $str;
                }
                elsif($line =~ /^\s*abstract = \)(Hat.*)\},$/) {
                    # Deal with one file with corrupt entry.
                    $data{'abstract'} = $1;
                }
                elsif($line =~ /^\s*\}$/) {
                    last DATA_LOOP;
                }
                elsif($line =~ /^\s*$/) {
                    warn "Found empty line before end of article $key in $filename\n";
                    last DATA_LOOP;
                }
                else {
                    warn "I don't know what to do with line:\n\n$prev_line\n$line\n\n...",
                        " in article $key in $filename, line $line_no\n";
                    warn "$msg\n" if $msg ne "NA";
                    last DATA_LOOP;
                }

                if($line =~ /^\s*doi\s*=\s*\{(.*)\}$/i) {
                    my $line_doi = $1;
                    if(!exists($data{'doi'})) {
                        warn "Missed DOI $line_doi in file $filename, line $line_no (article $key)\n";
                    }
                    elsif($data{'doi'} ne $line_doi) {
                        warn "Raw DOI $line_doi not the same as ", $data{'doi'},
                            " extracted from file $filename, line $line_no (article $key)\n";
                    }
                }

                $prev_line = $line;
            }
            
            my $n_deleted = 0;
            foreach my $data_key (keys(%data)) {
                if($data{$data_key} =~ /^\s*$/) {
                    $n_deleted++;
                    delete $data{$data_key};
                }
            }
            if($n_deleted > 0) {
                $last_read_issues{'null entries'} += $n_deleted;
                $last_read_issues{'articles with null entries'}++;
            }

            push(@articles, \%data);
            $prev_line = $line;
        }
    }

    close(BIB);

    return @articles;
}

##############################################################################
# author_list(bibtex)
#
#   ###  #   # ##### #   #  ###  ####        #      ###   #### #####
#  #   # #   #   #   #   # #   # #   #       #       #   #       #  
#  ##### #   #   #   ##### #   # ####        #       #    ###    #  
#  #   # #   #   #   #   # #   # #   #       #       #       #   #  
#  #   #  ###    #   #   #  ###  #   #       #####  ###  ####    #  
#                                      #####                        
#                                                                   
# Return a list of authors from a bibtex entry. If the author entry is not
# defined, then the list will be empty.
##############################################################################

sub author_list {
    my ($bibtex) = @_;

    my @authors;

    return @authors if !exists($bibtex->{'author'});

    # This assumes no-one is called 'and', when presumably
    # curly brackets would be deployed. However, having done this:
    # grep -i -h 'author *=' bibtex/*/*.bib | sed -e 's/[Aa]uthor *= *{//' -e 's/},$//' | grep '{'
    # the only result returned is {[}Anonymous] (in the Web of Science,
    # which &tidy_bib will take out) 
    @authors = split(/ and /i, $bibtex->{'author'});

    return @authors;
}

##############################################################################
#
#  ##### ####   ###  #####  ###  ####        #      ###   #### #####
#  #     #   #   #     #   #   # #   #       #       #   #       #  
#  ####  #   #   #     #   #   # ####        #       #    ###    #  
#  #     #   #   #     #   #   # #   #       #       #       #   #  
#  ##### ####   ###    #    ###  #   #       #####  ###  ####    #  
#                                      #####                        
#                                                                   
##############################################################################

sub editor_list {
    my ($bibtex) = @_;

    my @editors;

    return @editors if !exists($bibtex->{'editor'});

    @editors = split(/ and /i, $bibtex->{'editor'});
    return @editors;
}

##############################################################################
#
#  #   #        ###  #   # ##### #   #  ###  ####   ####
#  ##  #       #   # #   #   #   #   # #   # #   # #    
#  # # #       ##### #   #   #   ##### #   # ####   ### 
#  #  ##       #   # #   #   #   #   # #   # #   #     #
#  #   #       #   #  ###    #   #   #  ###  #   # #### 
#        #####                                          
#                                                       
##############################################################################

sub n_authors {
    my ($bibtex) = @_;

    if(exists($bibtex->{'author'})) {
        my @authors = &author_list($bibtex);
        return scalar(@authors);
    }
    else {
        return 0;
    }
}

##############################################################################
#
#  #   #       ##### ####   ###  #####  ###  ####   ####
#  ##  #       #     #   #   #     #   #   # #   # #    
#  # # #       ####  #   #   #     #   #   # ####   ### 
#  #  ##       #     #   #   #     #   #   # #   #     #
#  #   #       ##### ####   ###    #    ###  #   # #### 
#        #####                                          
#                                                       
##############################################################################

sub n_editors {
    my ($bibtex) = @_;

    if(exists($bibtex->{'editor'})) {
        my @editors = &editor_list($bibtex);
        return scalar(@editors);
    }
    else {
        return 0;
    }
}

##############################################################################
#
#   ###  #   # ##### #   #  ###  ####         #### #   # ####  #   #  ###  #   # #####  ####
#  #   # #   #   #   #   # #   # #   #       #     #   # #   # ##  # #   # ## ## #     #    
#  ##### #   #   #   ##### #   # ####         ###  #   # ####  # # # ##### # # # ####   ### 
#  #   # #   #   #   #   # #   # #   #           # #   # #   # #  ## #   # #   # #         #
#  #   #  ###    #   #   #  ###  #   #       ####   ###  #   # #   # #   # #   # ##### #### 
#                                      #####                                                
#                                                                                           
##############################################################################

sub author_surnames {
    my ($bibtex) = @_;

    return &get_surnames(&author_list($bibtex));
}

##############################################################################
#
#  ##### ####   ###  #####  ###  ####         #### #   # ####  #   #  ###  #   # #####  ####
#  #     #   #   #     #   #   # #   #       #     #   # #   # ##  # #   # ## ## #     #    
#  ####  #   #   #     #   #   # ####         ###  #   # ####  # # # ##### # # # ####   ### 
#  #     #   #   #     #   #   # #   #           # #   # #   # #  ## #   # #   # #         #
#  ##### ####   ###    #    ###  #   #       ####   ###  #   # #   # #   # #   # ##### #### 
#                                      #####                                                
#                                                                                           
##############################################################################

sub editor_surnames {
    my ($bibtex) = @_;

    return &get_surnames(&editor_list($bibtex));
}

##############################################################################
#
#   #### ##### #####        #### #   # ####  #   #  ###  #   # #####  ####
#  #     #       #         #     #   # #   # ##  # #   # ## ## #     #    
#  #  ## ####    #          ###  #   # ####  # # # ##### # # # ####   ### 
#  #   # #       #             # #   # #   # #  ## #   # #   # #         #
#   #### #####   #         ####   ###  #   # #   # #   # #   # ##### #### 
#                    #####                                                
#                                                                         
##############################################################################

sub get_surnames {
    my @names = @_;

    my @surnames;

    foreach my $au (@names) {
        if($au =~ /,/) {
            my ($sn) = split(/,/, $au);
            $sn =~ s/^\s+//;
            $sn =~ s/\s+$//;
            push(@surnames, &tc_author($sn));
        }
        else {
            $au =~ s/\s+$//;
            my @name_words = split(" ", $au);
            push(@surnames, &tc_author($name_words[$#name_words]));
        }
    }

    return @surnames;
}

##############################################################################
#
#   ###  #   # ##### #   #  ###  ####         ###  #   #  ###  #####  ###   ###  #      ####
#  #   # #   #   #   #   # #   # #   #         #   ##  #   #     #     #   #   # #     #    
#  ##### #   #   #   ##### #   # ####          #   # # #   #     #     #   ##### #      ### 
#  #   # #   #   #   #   # #   # #   #         #   #  ##   #     #     #   #   # #         #
#  #   #  ###    #   #   #  ###  #   #        ###  #   #  ###    #    ###  #   # ##### #### 
#                                      #####                                                
#                                                                                           
##############################################################################

sub author_initials {
    my ($bibtex) = @_;

    return &get_initials(&author_list($bibtex));
}

##############################################################################
#
#  ##### ####   ###  #####  ###  ####         ###  #   #  ###  #####  ###   ###  #      ####
#  #     #   #   #     #   #   # #   #         #   ##  #   #     #     #   #   # #     #    
#  ####  #   #   #     #   #   # ####          #   # # #   #     #     #   ##### #      ### 
#  #     #   #   #     #   #   # #   #         #   #  ##   #     #     #   #   # #         #
#  ##### ####   ###    #    ###  #   #        ###  #   #  ###    #    ###  #   # ##### #### 
#                                      #####                                                
#                                                                                           
##############################################################################

sub editor_initials {
    my ($bibtex) = @_;

    return &get_initials(&editor_list($bibtex));
}

##############################################################################
#
#   #### ##### #####        ###  #   #  ###  #####  ###   ###  #      ####
#  #     #       #           #   ##  #   #     #     #   #   # #     #    
#  #  ## ####    #           #   # # #   #     #     #   ##### #      ### 
#  #   # #       #           #   #  ##   #     #     #   #   # #         #
#   #### #####   #          ###  #   #  ###    #    ###  #   # ##### #### 
#                    #####                                                
#                                                                         
##############################################################################

sub get_initials {
    my @names = @_;

    my @initials;

    foreach my $au (@names) {
        $au =~ s/\s+$//;
        if($au =~ /,/) {
            my @parts = split(/,/, $au);
            $au = $parts[$#parts];
            $au =~ s/^\s+$//;
            push(@initials, &initialify($au));
        }
        else {
            my @parts = split(" ", $au);
            $au = join(" ", pop(@parts));
            # Assume all the words except the last are first names
            push(@initials, &initialify($au));
        }
    }

    return @initials;
}

##############################################################################
#
#   ###  #   #  ###  #####  ###   ###  #      ###  ##### #   #
#    #   ##  #   #     #     #   #   # #       #   #      # # 
#    #   # # #   #     #     #   ##### #       #   ####    #  
#    #   #  ##   #     #     #   #   # #       #   #       #  
#   ###  #   #  ###    #    ###  #   # #####  ###  #       #  
#                                                             
# 'Make initials from' a string of space and dash separated words
##############################################################################

sub initialify {
    my ($forenames) = @_;

    my @name_words = split(" ", $forenames);
    my $inits = "";
    foreach my $name_word (@name_words) {
        next if length($name_word) == 0;
        if($name_word eq uc($name_word)) {
            # e.g. JG or J.G. or J.-G. or J-G
            foreach my $chr (split(//, $name_word)) {
                next if $chr eq '.';
                if($name_word eq '-') {
                    $inits =~ s/\s+$//;
                    $inits .= $chr;
                }
                else {
                    $inits .= $chr.". ";
                }
            }
        }
        elsif($name_word =~ /-/) {
            # e.g. John-Gareth
            foreach my $dashed (split(/-/, $name_word)) {
                $inits .= uc(substr($dashed, 0, 1)).".-";
            }
            $inits =~ s/-$//;
        }
        else {
            # e.g. John
            $inits .= uc(substr($name_word, 0, 1)).". ";
        }
    }
    $inits =~ s/\s+$//;

    return $inits;
}

##############################################################################
#
#   #### #     #####  ###  #   #        ###  #   # ##### #   #  ###  ####   ####
#  #     #     #     #   # ##  #       #   # #   #   #   #   # #   # #   # #    
#  #     #     ####  ##### # # #       ##### #   #   #   ##### #   # ####   ### 
#  #     #     #     #   # #  ##       #   # #   #   #   #   # #   # #   #     #
#   #### ##### ##### #   # #   #       #   #  ###    #   #   #  ###  #   # #### 
#                                #####                                          
#                                                                               
##############################################################################

sub clean_authors {
    my ($bibtex) = @_;

    return &clean_names(&author_list($bibtex));
}

##############################################################################
#
#   #### #     #####  ###  #   #       ##### ####   ###  #####  ###  ####   ####
#  #     #     #     #   # ##  #       #     #   #   #     #   #   # #   # #    
#  #     #     ####  ##### # # #       ####  #   #   #     #   #   # ####   ### 
#  #     #     #     #   # #  ##       #     #   #   #     #   #   # #   #     #
#   #### ##### ##### #   # #   #       ##### ####   ###    #    ###  #   # #### 
#                                #####                                          
#                                                                               
##############################################################################

sub clean_editors {
    my ($bibtex) = @_;

    return &clean_names(&editor_list($bibtex));
}

##############################################################################
#
#   #### #     #####  ###  #   #       #   #  ###  #   # #####  ####
#  #     #     #     #   # ##  #       ##  # #   # ## ## #     #    
#  #     #     ####  ##### # # #       # # # ##### # # # ####   ### 
#  #     #     #     #   # #  ##       #  ## #   # #   # #         #
#   #### ##### ##### #   # #   #       #   # #   # #   # ##### #### 
#                                #####                              
#                                                                   
##############################################################################

sub clean_names {
    my @names = @_;

    my @surnames = &get_surnames(@names);
    my @initials = &get_initials(@names);

    my @clean;
    for(my $i = 0; $i <= $#surnames; $i++) {
        if(length($initials[$i]) > 0) {
            push(@clean, $surnames[$i].", ".$initials[$i]);
        }
        else {
            push(@clean, $surnames[$i]);
        }
    }
    return @clean;
}

##############################################################################
#
#   #### #     #####  ###  #   #        ###  #     #####        ###  #   # ##### #   #
#  #     #     #     #   # ##  #       #   # #       #         #   # #   #   #   #   #
#  #     #     ####  ##### # # #       ##### #       #         ##### #   #   #   #####
#  #     #     #     #   # #  ##       #   # #       #         #   # #   #   #   #   #
#   #### ##### ##### #   # #   #       #   # #####   #         #   #  ###    #   #   #
#                                #####                   #####                        
#                                                                                     
# A procedure necessitated because sometimes Chinese authors' firstnames
# and surnames are swapped in different entries.
##############################################################################


sub clean_alt_auth {
    my ($bibtex) = @_;

    return &clean_alt_names(&author_list($bibtex));
}

##############################################################################
#
#   #### #     #####  ###  #   #        ###  #     #####       ##### #### 
#  #     #     #     #   # ##  #       #   # #       #         #     #   #
#  #     #     ####  ##### # # #       ##### #       #         ####  #   #
#  #     #     #     #   # #  ##       #   # #       #         #     #   #
#   #### ##### ##### #   # #   #       #   # #####   #         ##### #### 
#                                #####                   #####            
#                                                                         
##############################################################################

sub clean_alt_ed {
    my ($bibtex) = @_;

    return &clean_alt_names(&editor_list($bibtex));
}

##############################################################################
#
#   #### #     #####  ###  #   #        ###  #     #####       #   #  ###  #   # #####  ####
#  #     #     #     #   # ##  #       #   # #       #         ##  # #   # ## ## #     #    
#  #     #     ####  ##### # # #       ##### #       #         # # # ##### # # # ####   ### 
#  #     #     #     #   # #  ##       #   # #       #         #  ## #   # #   # #         #
#   #### ##### ##### #   # #   #       #   # #####   #         #   # #   # #   # ##### #### 
#                                #####                   #####                              
#                                                                                           
##############################################################################

sub clean_alt_names {
    my @names = @_;

    my @alt_clean;
    foreach my $au (@names) {
        my $initials;
        my $surname;
        if($au =~ /,/) {
            # The BibTeX code has a surname, (jnr. etc.,) forenames
            # But we want to treat the forenames as though they were
            # the surname, and the surname as though it is forename
            my @parts = split(/,/, $au);
            my $part1 = $parts[0];
            $part1 =~ s/^\s+//;
            $part1 =~ s/\s+$//;
            $initials = &initialify($part1);
            my $part2 = $parts[$#parts];
            $part2 =~ s/^\s+//;
            $part2 =~ s/\s+$//;
            $surname = &tc_author($part2);
        }
        else {
            # The BibTeX code is a series of words. The first
            # word is to be treated as a surname, the remaining
            # words as forenames
            my @parts = split(" ", $au);
            my $part1 = shift(@parts);
            $surname = &tc_author($part1);
            my $part2 = join(" ", @parts);
            $initials = &initialify($part2);
        }
        if(length($initials) > 0) {
            push(@alt_clean, "$surname, $initials");
        }
        else {
            push(@alt_clean, $surname);
        }
    }
    return @alt_clean;
}

##############################################################################
#
#   #### #   # ####         ###  #   # ##### #   #  ###  ####   ####
#  #     ## ## #   #       #   # #   #   #   #   # #   # #   # #    
#  #     # # # ####        ##### #   #   #   ##### #   # ####   ### 
#  #     #   # #           #   # #   #   #   #   # #   # #   #     #
#   #### #   # #           #   #  ###    #   #   #  ###  #   # #### 
#                    #####                                          
#                                                                   
##############################################################################

sub cmp_authors {
    my ($bib1, $bib2, $alt) = @_;

    $alt = 0 if !defined($alt);

    my @clean1 = &clean_authors($bib1);
    my @clean2 = &clean_authors($bib2);
    my @clalt1;
    my @clalt2;
    if($alt) {
        @clalt1 = &clean_alt_auth($bib1);
        @clalt2 = &clean_alt_auth($bib2);
    }
    return &cmp_names(\@clean1, \@clean2, \@clalt1, \@clalt2);
}

##############################################################################
#
#   #### #   # ####        ##### ####   ###  #####  ###  ####   ####
#  #     ## ## #   #       #     #   #   #     #   #   # #   # #    
#  #     # # # ####        ####  #   #   #     #   #   # ####   ### 
#  #     #   # #           #     #   #   #     #   #   # #   #     #
#   #### #   # #           ##### ####   ###    #    ###  #   # #### 
#                    #####                                          
#                                                                   
##############################################################################

sub cmp_editors {
    my ($bib1, $bib2, $alt) = @_;

    $alt = 0 if !defined($alt);

    my @clean1 = &clean_editors($bib1);
    my @clean2 = &clean_editors($bib2);
    my @clalt1;
    my @clalt2;
    if($alt) {
        @clalt1 = &clean_alt_ed($bib1);
        @clalt2 = &clean_alt_ed($bib2);
    }
    return &cmp_names(\@clean1, \@clean2, \@clalt1, \@clalt2);
}

##############################################################################
#
#   #### #   # ####        #   #  ###  #   # #####  ####
#  #     ## ## #   #       ##  # #   # ## ## #     #    
#  #     # # # ####        # # # ##### # # # ####   ### 
#  #     #   # #           #  ## #   # #   # #         #
#   #### #   # #           #   # #   # #   # ##### #### 
#                    #####                              
#                                                       
##############################################################################

sub cmp_names {
    my ($clean1, $clean2, $clalt1, $clalt2) = @_;

    my $alt = (scalar(@$clalt1) > 0) ? 1 : 0;

    my $n_same = 0;
    for(my $i = 0; $i <= $#$clean1 && $i <= $#$clean2; $i++) {
        if($$clean1[$i] eq $$clean2[$i]) {
            $n_same += $surname_initials_eq;
        }
        elsif($alt && ($$clean1[$i] eq $$clalt2[$i] || $$clalt1[$i] eq $$clean2[$i])) {
            $n_same += $surname_initials_eq;
        }
        else {
            my $cl1 = (split(/,/, $$clean1[$i]))[0];
            my $cl2 = (split(/,/, $$clean2[$i]))[0];
            my ($al1, $al2);
            if($alt) {
                $al1 = (split(/,/, $$clalt1[$i]))[0];
                $al2 = (split(/,/, $$clalt2[$i]))[0];
            }
            if($cl1 eq $cl2) {
                $n_same += $surname_eq;
            }
            elsif($alt && ($cl1 eq $al2 || $al1 eq $cl2)) {
                $n_same += $surname_eq;
            }
        }
    }

    return $n_same;
}

##############################################################################
#
#  #####  ####        ###  #   # ##### #   #  ###  #### 
#    #   #           #   # #   #   #   #   # #   # #   #
#    #   #           ##### #   #   #   ##### #   # #### 
#    #   #           #   # #   #   #   #   # #   # #   #
#    #    ####       #   #  ###    #   #   #  ###  #   #
#              #####                                    
#                                                       
##############################################################################

sub tc_author {
    my ($word) = @_;

    my $tc_word = "";

    foreach my $name (split(/([- ])/, $word)) {
        if($name eq "-") {
            $tc_word .= "-" if(substr($tc_word, -1) ne "-");
        }
        elsif($name eq " ") {
            $tc_word .= " " if(substr($tc_word, -1) ne " ");
        }
        elsif($name ne "") {
            $tc_word .= uc(substr($name, 0, 1));
            $tc_word .= lc(substr($name, 1)) if(length($name) > 1);
        }
    }

    return $tc_word;
}

##############################################################################
# debibtex_doi (doi)
#
#  ####  ##### ####   ###  ####  ##### ##### #   #       ####   ###   ### 
#  #   # #     #   #   #   #   #   #   #      # #        #   # #   #   #  
#  #   # ####  ####    #   ####    #   ####    #         #   # #   #   #  
#  #   # #     #   #   #   #   #   #   #      # #        #   # #   #   #  
#  ####  ##### ####   ###  ####    #   ##### #   #       ####   ###   ### 
#                                                  #####                  
#                                                                         
# Remove BibTeX code from a DOI entry. This is risky because theoretically
# these could be legitmate DOI characters
##############################################################################

sub debibtex_doi {
    my ($doi) = @_;

    $doi =~ s/\\//g;
    $doi =~ s/\{\[\}/\[/g;
    $doi = lc($doi);

    return $doi
}

##############################################################################
# count_chrs (chr, in, escape)
#
#   ####  ###  #   # #   # #####        #### #   # ####   ####
#  #     #   # #   # ##  #   #         #     #   # #   # #    
#  #     #   # #   # # # #   #         #     ##### ####   ### 
#  #     #   # #   # #  ##   #         #     #   # #   #     #
#   ####  ###   ###  #   #   #          #### #   # #   # #### 
#                                #####                        
#                                                             
# Count the number of times a specific character appears in a string. $chr
# should have length one; $in is what to check
##############################################################################

sub count_chrs {
    my ($chr, $in, $escape) = @_;

    die "BUG! In count_chrs(\"$chr\", \"$in\", \"$escape\"), "
        ."first arg not of length 1\n" if(length($chr) ne 1);

    my $n = 0;
    my $prev_c = "";
    foreach my $c (split(//, $in)) {
        $n++ if($c eq $chr && (!defined($escape) || $prev_c ne $escape));
        $prev_c = $c;
    }
    return $n;
}

1;
