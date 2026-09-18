#!/usr/bin/perl
#
# Rewritten script of slr-review.pl, which in the end has become too messy
# to fix after the implementation of slr-db-merge.pl. Expect cutting and
# pasting of code between the two.
#
# The jobs of this script are as follows:
#
#   1. Match the bibliography from slr-db-merge.pl against the set of 
#      papers that were screened and the set of papers that were
#      reviewed.
#
#   2. Confirm the logic behind the selection of papers that were
#      screened.
#
#   3. Confirm that all papers that needed to be reviewed have been
#      reviewed.
#
#   4. Process the reviews from the Google Form, and match them
#      with the bibliography.
#
#   5. Generate and save results and associated data
#
#       (a) .bib files for each step of the process
#
#       (b) .tex and .csv files for any results tables and data
#
#       (c) .pdf file for any visualizations. Those proposed:
#
#           * Distributions of time period and spatial extent (RQ1)
#               + This and other distributions should compare HPC with PC only
#           * Distributions of numbers of agents (RQ2)
#           * Distributions of numbers of simulations (RQ3)
#           * Summaries of limitations (RQ4)
#           * Classification of Q1, Q2 and Q3 against search strings, ASJC
#             classes, and journal sources
#           * Ditto for mentions of and types of computing resource used
#
#       (d) .html files for sankey plots showing paper flows

use strict;
use warnings;

use JSON;
use POSIX;
use Digest::MD5 qw (md5_hex);
use File::Spec;

my $dir;
BEGIN { # Sorry Doug :-)
    use File::Basename;
    $dir = dirname($0);
    push(@INC, "./$dir/lib");
}

use CSV;
use Latin;
use WoS;
use Convert;
use BibTeX;
use TextTK;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

sub iso_date {
    my ($sec, $min, $hr, $day, $mon, $yr) = gmtime();

    return sprintf("%04d-%02d-%02dT%02d:%02d:%02d", $yr + 1900, $mon + 1, $day, $hr, $min, $sec);
}

################################################################################
#                                                                              #
#  #### #      ###  ####   ###  #      ####                                    #
# #     #     #   # #   # #   # #     #                                        #
# #  ## #     #   # ####  ##### #      ###                                     #
# #   # #     #   # #   # #   # #         #                                    #
#  #### #####  ###  ####  #   # ##### ####                                     #
#                                                                              #
################################################################################

my %input_files = (
    'bibtex' => 'merged.bib',
    'merge-output' => 'slr-db-merge.out',
    'dodgy-dois' => 'dodgy-dois.csv',
    'corpus' => 'no_dups.corpus_combination.csv',
    'screen' => 'full-text-corpus-with-uids.csv',
    'screen-results' => 'screened/slr-screening-results-users.json',
    'review-assign' => 'screened/who-reads-screened-papers.csv',
    'review' => 'screened/reviews/ExAMPLER SLR form.csv'
);
my %output_files = (
    'sankey-papers' => 'sankey-plot-papers.html',
    'sankey-cats' => 'sankey-plot-cats.html',
    'sankey-topics' => 'sankey-plot-topics.html',
    'sankey-topics-intent' => 'sankey-plot-topics-intent.html',
    'cloud-title-review' => 'wordcloud-title-review.html',
    'cloud-title-reject' => 'wordcloud-title-reject.html',
    'cloud-title-dispute' => 'wordcloud-title-dispute.html',
    'cloud-abstract-review' => 'wordcloud-abstract-review.html',
    'cloud-abstract-reject' => 'wordcloud-abstract-reject.html',
    'cloud-abstract-dispute' => 'wordcloud-abstract-dispute.html',
    'data-screening' => 'data-screening.csv',
    'table-asjc-conf' => 'asjc-conf.tex',
    'table-wos-conf' => 'wos-conf.tex',
    'table-asjc-wos' => 'asjc-wos-conf.tex',
    'table-asjc-wos-short' => 'asjc-wos-summary.tex',
    'table-asjc-short' => 'asjc-summary.tex',
    'table-inc-wos' => 'wos-included-categories.tex',
    'table-sources' => 'top-sources.tex',
    'table-src-inc' => 'top-category-sources.tex',
    'table-journals' => 'journals.tex',
    'table-mi-all' => 'mutinf-unanimous.tex',
    'table-mi-any' => 'mutinf-anyone.tex',
    'table-mi-jasss' => 'mutinf-jasss.tex',
    'table-mi-review' => 'mutinf-review.tex',
    'R-script' => 'slr-results.R',
    'pdf-file' => 'slr-results.pdf',
    'R-merged-bib' => 'slr-final.bib',
    'R-screen-bib' => 'slr-screened.bib',
    'R-review-bib' => 'slr-reviewed.bib',
    'R-interest-bib' => 'slr-interesting.bib',
    'R-prisma-flow' => 'slr-prisma-flow.tex',
);

my %pdf_files = (
    'bar-dl-soc-v-comp' => 'soc-v-comp-downloaded.pdf',
    'bar-scr-soc-v-comp' => 'soc-v-comp-screening.pdf',
    'bar-rev-soc-v-comp' => 'soc-v-comp-reviewing.pdf',
    'bar-res-soc-v-comp' => 'soc-v-comp-results.pdf',
    'bar-journal-stage' => 'stage-journals.pdf',
    'bar-cat-stage' => 'stage-cats.pdf',
    'bar-asjc-stage' => 'stage-asjc.pdf',
    'bar-topic-stage' => 'stage-topics.pdf',
    'bar-intent-stage' => 'stage-topics-indent.pdf',
    'bar-space-scale' => 'space-scale.pdf',
    'bar-space-type' => 'space-type.pdf',
    'bar-time-scale' => 'time-scale.pdf',
    'bar-agent-scale' => 'agent-scale.pdf',
    'bar-agent-types' => 'agent-types.pdf',
    'grid-space-time-hpc' => 'space-time-hpc.pdf',
    'grid-space-time-pc' => 'space-time-pc.pdf',
    'grid-space-time-maybe' => 'space-time-maybe.pdf',
    'grid-space-time-na' => 'space-time-na.pdf',
    'grid-space-time-all' => 'space-time-all.pdf',
    'hist-space-size-px' => 'space-size-pixels.pdf',
    'hist-space-size-ft' => 'space-size-features.pdf',
    'hist-time-size' => 'time-size.pdf',
    'hist-agent-size' => 'agent-size.pdf',
    'hist-agent-ratio' => 'agent-ratio.pdf',
    'hist-runs' => 'runs.pdf',
    'hist-agent-types' => 'agent-n-types.pdf',
    'hist-comp' => 'comp-scale.pdf',
    'ts-space-size-px' => 'space-size-pixels-ts.pdf',
    'ts-space-size-ft' => 'space-size-features-ts.pdf',
    'ts-time-size' => 'time-size-ts.pdf',
    'ts-agent-size' => 'agent-size-ts.pdf',
    'ts-runs' => 'runs-ts.pdf',
    'bar-limits' => 'limits-any.pdf',
    'bar-limits-model' => 'limits-model.pdf',
    'bar-limits-future' => 'limits-future.pdf',
    'bar-mutinfs' => 'mutual-information.pdf',
    'bar-comp' => 'comp-types.pdf',
    'bar-org-hpc' => 'hpc-orgs.pdf',
    'map-affil-hpc' => 'hpc-map.pdf',
    'map-affil-pc' => 'pc-map.pdf',
    'map-affil-all' => 'results-map.pdf',
    'map-case-all' => 'cases-map.pdf'
);

my %parameters = (
    'output-dir' => 'slr-results',
    'merge-dir' => 'slr-merge-2025-09-04',
    'pdf-dir' => 'figs',
    'sankey-dir' => 'sankeys',
    'cloud-dir' => 'clouds',
    'R-bib-dir' => 'bib',
    'tex-dir' => 'tex',
    'plots-bw' => 1,
    'bar-p' => 0,
    'bar-n' => 1,
    'hist-bw' => 1,
    'hist-p' => 0,
    'sankey-fontsize' => 18,
    'sankey-barwidth' => 100,
    'top-any-cat' => 3,
    'top-all-cat' => 20,
    'cloud-min-fontsize' => 10,
    'cloud-font-family' => 'Noto Sans, Sans-Serif', # Noto Sans is JASSS's body text font
    'table-format' => 'JASSS', # 'LNCS' is the alternative
    'text-size' => 1.2,
    'R-bib-max-auth' => 3,
    'R-bib-max-twords' => 5,
    'R-do-cloud' => 0,
    'R-do-sankey' => 0,
    'R-do-table-mi' => 0,
    'R-overwrite' => 1,
    'R-overdate' => 1,
    'tables-rq-prefix' => 'R',
    'R-progress-interval' => 20,
);

my @bools = ('plots-bw', 'bar-p', 'bar-n', 'hist-bw', 'hist-p', 'R-do-cloud', 'R-do-sankey',
    'R-do-table-mi', 'R-overwrite');
my %boolean_param;
foreach my $param (@bools) {
    $boolean_param{$param} = 1;
}
my @required_fields = (['year'], ['author'], ['title'], ['journal', 'booktitle']);
my %missing_field_counts;
my %lookup_wins;
my %lookup_loss;

my %dodgy_dois;  # DOI found by slr-db-merge.pl to be 'dodgy'

my %ix_citekey;  # Index by citekey (expected to be unique) -> ix
my %ix_doi;      # Index by DOI, _WoS_doi, _Scopus_doi (may not be unique) -> {ixes...}
my %ix_md5;      # Index by MD5 of title.journal &orig_text()ed -> {ixes...}
my %ix_title;    # Index by &orig_text(title, _WoS_title, _Scopus_title) -> {ixes...}
my %ix_abstract; # Index by md5(&orig_text(abstract, _WoS_abstract, _Scopus_abstract)) -> {ixes...}

my %index = (
    '_bibkey' => \%ix_citekey,
    'doi' => \%ix_doi,
    'title' => \%ix_title,
    'abstract' => \%ix_abstract,
    '__md5' => \%ix_md5
);
my %db2corpus;  # Index in bibtex to index in corpus (one-one)
my %corpus2db;  # Index in corpus to index in bibtex (one-one)
my %db2screen;  # Index in bibtex to index in screen (one-one)
my %screen2db;  # Index in screen to index in bibtex (one-one)
my %db2scrres;  # Index in bibtex to index in scrres (one-one)
my %scrres2db;  # Index in scrres to index in bibtex (one-one)
my %db2assign;  # Index in bibtex to index in assign (one-one)
my %assign2db;  # Index in assign to index in bibtex (one-one)
my %db2merged;  # Index in bibtex to index in merged review (one-one)
my %merged2db;  # Index in merged review to index in bibtex (one-one)
my %rev2ass;    # Index in review to index in assign (many-one)
my %biblio;     # __source -> year -> surname -> [Indexes in db]

# Logbook function
my $logfile = $parameters{'output-dir'}.'/slr-results.log';
my $log_fp;

sub logbook {
    my @msg = @_;

    if(!defined($log_fp)) {
        open($log_fp, ">:encoding(UTF-8)", $logfile) or die "Cannot create log file $logfile: $!\n";
    }
    my $cmd = (File::Spec->splitpath($0))[2];

    $msg[$#msg] .= "\n" if(substr($msg[$#msg], -1) ne "\n");
    print $log_fp "$cmd log (", &iso_date(), "): ", join("", @msg);
}

# R
my $Rcmd = "R --no-save";
my @R_LIBS = ("latex2exp", "ggplot2", "maps", "stringr");
my $R_FP;

################################################################################
#                                                                              #
#  ####  ###  #   #  #### #####  ###  #   # #####  ####                        #
# #     #   # ##  # #       #   #   # ##  #   #   #                            #
# #     #   # # # #  ###    #   ##### # # #   #    ###                         #
# #     #   # #  ##     #   #   #   # #  ##   #       #                        #
#  ####  ###  #   # ####    #   #   # #   #   #   ####                         #
#                                                                              #
################################################################################

# Indexes in @corpus and @screen
my $R_DOI = 0;
my $R_MD5 = 1;
my $R_DB = 2;
my $R_TTL = 3;
my $R_ABS = 4;
my $R_CAT = 5;
my $R_JNL = 6;

# Indexes in @scrres
my $S_DOI = 0;
my $S_MD5 = 1;
my $S_Q1 = 2;
my $S_Q2 = 3;
my $S_Q3 = 4;

# Indexes in @assign
my $A_DOI = 0;
my $A_MD5 = 1;
my $A_R1 = 2;
my $A_R2 = 3;
my $A_RV1 = 4;
my $A_RV2 = 5;

# Google review form indexes and field names

my $GTIME = 0;          # Google Form timestamp
my $GWHO = 1;           # Google Form person who entered the data
my $GAUTH = 2;          # Google Form author surname
my $GYEAR = 3;          # Google Form paper year
my $GJOURN = 4;         # Google Form journal
my $GVOL = 5;           # Google Form volume
my $GISS = 6;           # Google Form issue
my $GPAGES = 7;         # Google Form pages
my $GISABM = 8;         # Google Form is it an ABM?
my $GISSOC = 9;         # Google Form is it social science?
my $GISEMP = 10;        # Google Form is it empirical?
my $GISSPINF = 11;      # Google Form is spatial information given?
my $GSPEXT = 12;        # Google Form spatial extent
my $GSPNAM = 13;        # Google Form name of spatial extent
my $GSPTY = 14;         # Google Form space type
my $GISSPN = 15;        # Google Form is space number of entities given?
my $GSPRAS = 16;        # Google Form number of raster entities
my $GSPVEC = 17;        # Google Form number of vector entities
my $GNSTEP = 18;        # Google Form number of time steps
my $GSTEPTY = 19;       # Google Form step type
my $GSOCTY = 20;        # Google Form social entity types
my $GNAGENT = 21;       # Google Form number of agents
my $GAGTY = 22;         # Google Form agent types
my $GNAGRW = 23;        # Google Form number of agents in the real world
my $GNRUN = 24;         # Google Form number of runs
my $GISCOMPINF = 25;    # Google Form is computing information provided
my $GCOMPTY = 26;       # Google Form computing environment type
my $GISCOMPLIM = 27;    # Google Form is computing limits used to justify model design
my $GLIMPHR = 28;       # Google Form computing limit phrases
my $GLIMTY = 29;        # Google Form type of computing limit
my $GISINT = 30;        # Google Form is this an interesting paper
my $GISHPC = 31;        # Derived Google Form was an HPC option selected
my %google_form = (
    "Timestamp" => $GTIME,
    "Username" => $GWHO,
    "First author's surname" => $GAUTH,
    "Year of publication" => $GYEAR,
    "Which journal is the paper in?" => $GJOURN,
    "Journal volume identifier" => $GVOL,
    "Issue number" => $GISS,
    "Page range or article number" => $GPAGES,
    "Is this paper about an agent-based model?" => $GISABM,
    "Is this paper about a model in the social sciences?" => $GISSOC,
    "Does the model simulate an empirical, contemporary case study?" => $GISEMP,
    "Does the paper provide any information about the spatial extent of the model?" => $GISSPINF,
    "What is the spatial extent simulated in the model?" => $GSPEXT,
    "What is the name given by the authors in the paper to the area simulated?" => $GSPNAM,
    "How is space represented in the model?" => $GSPTY,
    "Does the paper say how many pixels, patches, cells and/or polygons?" => $GISSPN,
    "Number of pixels, patches or cells" => $GSPRAS,
    "Number of polygons, lines, points or 'features'" => $GSPVEC,
    "How many time steps are in the model?" => $GNSTEP,
    "What sort of time scale do the time steps represent?" => $GSTEPTY,
    "Which social entities are represented as agents in the model?" => $GSOCTY,
    "How many agents are simulated in the model?" => $GNAGENT,
    "Units of the number of agents" => $GAGTY,
    "How many of the above 'units' are there in the real case study?" => $GNAGRW,
    "How many runs of the model do the authors report having done?" => $GNRUN,
    "Do the authors provide any information about the computing equipment they used?" => $GISCOMPINF,
    "What computing equipment was used?" => $GCOMPTY,
    "Does the paper discuss any practical limitations on their work that might be fixed".
        " by access to more computing power?" => $GISCOMPLIM,
    "When describing or discussing the model, which of the following phrases (or similar)".
        " were used to suggest pragmatic constraints on the work?" => $GLIMPHR,
    "When discussing the model's limitations or any future work, which of the following ".
        "are mentioned in a way that suggests a superior study would have done them if ".
        "feasible?" => $GLIMTY,
    "Interesting?" => $GISINT
);

sub sort_by_hash {
    my ($a, $b, $hash, $na) = @_;

    $na = -1 if(!defined($na));

    if(exists($$hash{$a})) {
        return exists($$hash{$b}) ? ($$hash{$a} <=> $$hash{$b}) : $na;
    }
    elsif(exists($$hash{$b})) {
        return -1 * $na;
    }
    else {
        return $a cmp $b;
    }
}

my %space_order = (             # Answers to $GSPEXT
    'City' => 9,
    'Catchment of a River Basin' => 10,
    'County or Municipality' => 11,
    'Housing Estate' => 7,
    'More than one Nation, but not a whole Continent' => 15,
    'Multiple Counties or Region' => 12,
    'Nation' => 13,
    'Town' => 8,
    'Village' => 6,
    'World' => 20
);

sub sort_space { 
    my ($a, $b, $na) = @_;

    return &sort_by_hash($a, $b, \%space_order, $na);
}

my %how_space_order = (         # Answers to $GSPTY
    'Raster (cells, pixels, patches)' => 1,
    'Vector (polygons, lines, points)' => 2,
    'Mix of Raster and Vector' => 3,
    'Other' => 4,
    'Not a spatially explicit model' => 5,
);

sub sort_how_space {
    my ($a, $b, $na) = @_;

    return &sort_by_hash($a, $b, \%how_space_order, $na);
}

my %time_order = (              # Answers to $GSTEPTY
    'Seconds' => 1,
    'Minutes' => 2,
    'Hours' => 3,
    'Days' => 4,
    'Weeks' => 5,
    'Months' => 6,
    'Seasons / Quarters' => 7,
    'Years' => 8
);

sub sort_time {
    my ($a, $b, $na) = @_;

    return &sort_by_hash($a, $b, \%time_order, $na);
}

my %agent_order = (             # Answers to $GSOCTY and $GAGTY
    'Humans' => 1,
    'Human-Operated Machines' => 2,
    'Households' => 3,
    'Organizations' => 4,
    'Organizations (business, NGOs, etc.)' => 4,
    'Municipal/Local Governments' => 5,
    'National Governments' => 6,
);

sub sort_agent {
    my ($a, $b, $na) = @_;

    return &sort_by_hash($a, $b, \%agent_order, $na);
}

my %glimphr_map = (
    "Other modes of validation, participatory approaches to ABM" => 'Validation',
    "Availability of library with better network functionality" => 'Tools',
    "Computational limits of NetLogo" => 'Computing Time',
    "Too many rows of data in Excel (1.965m)" => 'Memory',
    "data" => 'Lack of Data',
    "due to limitations in both the implementation and the network generator" => 'Tools',
    "for the sake of simplicity" => 'Simplicity',
    "lack of data" => 'Lack of Data',
    "quality of data" => 'Lack of Data',
    "time taken to calibrate the model" => 'Computing Time',
    "to save computing power" => 'Computing Time',
    "to save computing time" => 'Computing Time',
    "to save disk space" => 'Storage',
    "to save memory" => 'Memory',
);

my %glimty_map = (
    "Other modes of validation, participatory approaches to ABM" => 'Validation',
    "Better calibration" => 'Calibration',
    "Better exogenous parameter values" => 'Calibration',
    "Coupling models together" => 'Integration',
    "Different network models" => 'Tools',
    "Different sensitivity analysis" => 'Uncertainty',
    "Improved optimization method" => 'Calibration',
    "Lack of data:  The problem aggravating this issue is the lack of reliable data".
        " concerning the dynamics of mobilisation of ethnic groups" => 'Lack of Data',
    "More cvalidation" => 'Validation',
    "More data" => 'Lack of Data',
    "More links in network to include family of student" => 'Network',
    "Multiple age bands" => 'Attributes',
    "No correct procedure for validating an ABM" => 'Validation',
    "Other implementation options" => 'Uncertainty',
    "changes in attributes of agents" => 'Dynamics',
    "covid" => 'Lack of Data', # Based on Ric's review and double-checking the paper
    "covid transmission probability ,vaccine efficacy" => 'Lack of Data',
    "generalization to other contexts" => 'Generalisation',
    "giving agents heterogeneous learning rates" => 'Attributes',
    "including new classes of agent" => 'Agent Types',
    "including other social processes" => 'Dynamics',
    "larger social network" => 'Network',
    "larger spatial extent" => 'Space',
    "less aggregated agents (e.g. simulating people not households)" => 'Agent Types',
    "more / other scenarios" => 'Scenarios',
    "more agents" => 'Agents',
    "more environmental dynamics" => 'Environment',
    "more fine-grained spatial representation" => 'Space',
    "more fine-grained temporal resolution" => 'Time',
    "more fine-grained temporal resolution, more attributes (demographic)" => 'Attributes',
    "more inteactions" => 'Dynamics',
    "more runs of the model" => 'Runs',
    "more scenarios" => 'Scenarios',
    "more complicated decision making algorithms" => 'Dynamics',
    "more data" => 'Lack of Data',
    "parallelization" => 'Tools',
    "validation" => 'Validation'
);

my %gspnam_ctry = ( # Search string in GSPNAM to region name in ggplot2's map_data()
    '12 European Countries' => ['Belgium', 'Denmark', 'Finland', 'France', 'Germany', 'Greece',
        'Ireland', 'Netherlands', 'Portugal', 'Spain', 'Sweden', 'UK'],
    'Afghanistan' => ['Afghanistan'],
    'Argentina' => ['Argentina'],
    'Australia' => ['Australia'],
    'Melbourne' => ['Australia'],
    'Austria' => ['Austria'],
    'Belgium' => ['Belgium'],
    'Brazil' => ['Brazil'],
    'Chile' => ['Chile'],
    'Canada' => ['Canada'],
    'Montreal' => ['Canada'],
    'Colombia' => ['Colombia'],
    'Beijing' => ['China'],
    'China' => ['China'],
    'Shanghai' => ['China'],
    'Galapagos' => ['Ecuador'],
    'Egypt' => ['Egypt'],
    'Ethiopia' => ['Ethiopia'],
    'France' => ['France'],
    'Germany' => ['Germany'],
    'Ghana' => ['Ghana'],
    'Greece' => ['Greece'],
    'Haiti' => ['Haiti'],
    'Hungary' => ['Hungary'],
    'India' => ['India'],
    'Indonesia' => ['Indonesia'],
    'Ireland' => ['Ireland'],
    'Italy' => ['Italy'],
    'Japan' => ['Japan'],
    'Kenya' => ['Kenya'],
    'Lebanon' => ['Lebanon'],
    'Nairobi' => ['Kenya'],
    'Kuwait' => ['Kuwait'],
    'Lesotho' => ['Lesotho'],
    'Laos' => ['Laos'],
    'Luxembourg' => ['Luxembourg'],
    'Malaysia' => ['Malaysia'],
    'Mozambique' => ['Mozambique'],
    'Ensenada' => ['Mexico'],
    'Mexico' => ['Mexico'],
    'Netherlands' => ['Netherlands'],
    'Westland' => ['Netherlands'],
    'New Zealand' => ['New Zealand'],
    'Niger' => ['Niger'],
    'Former Yugoslavia' => ['Bosnia and Herzegovina',
        'Croatia', 'Kosovo', 'Montenegro', 'North Macedonia', 'Serbia', 'Slovenia'],
    'Norway' => ['Norway'],
    'Poland' => ['Poland'],
    'Romania' => ['Romania'],
    'Saudi Arabia' => ['Saudi Arabia'],
    'Slovenia' => ['Slovenia'],
    'Somaliland' => ['Somalia'],
    'South Africa' => ['South Africa'],
    'Korea' => ['South Korea'], # Bit of an assumption, but not an unreasonable one
    'South Korea' => ['South Korea'],
    'Spain' => ['Spain'],
    'Switzerland' => ['Switzerland'],
    'Taiwan' => ['Taiwan'],
    'Tanzania' => ['Tanzania'],
    'Thailand' => ['Thailand'],
    'Turkey' => ['Turkey'],
    'Uganda' => ['Uganda'],
    'Aberdeen' => ['UK'],
    'England' => ['UK'],
    'London' => ['UK'],
    'Scotland' => ['UK'],
    'Tate Gallery' => ['UK'],
    'UK' => ['UK'],
    'America' => ['USA'], # Also something of an assumption!
    'Boston' => ['USA'],
    'California' => ['USA'],
    'Chicago' => ['USA'],
    'Detroit' => ['USA'],
    'Los Angeles' => ['USA'],
    'Louisiana' => ['USA'],
    'Oregon' => ['USA'],
    'Rhode Island' => ['USA'],
    'United States' => ['USA'],
    'U.S' => ['USA'],
    'USA' => ['USA'],
    'Venezuela' => ['Venezuela'],
    'Viet Nam' => ['Vietnam'],
    'Vietnam' => ['Vietnam'],
    'Zambia' => ['Zambia']
);

my %reviewers = (
    'Gary' => "Gary",
    'Richard' => "Richard",
    'Alison' => "Alison",
    'Doug' => "Doug",
    'Ric' => "Ric",
);

my %scopus_cats = (
    # Full list of 'ASJC' subject areas downloaded from
    # https://supportcontent.elsevier.com/RightNow%20Next%20Gen/SciVal/ASJC1.xlsx
    # On 19 November 2024
    'Multidisciplinary.bib' => 'Multidisciplinary',
    'AgriculturalBiologicalSciences.bib' => 'Agricultural and Biological Sciences', 
    'ArtsHumanities.bib' => 'Arts and Humanities', 
    # N.B. Biochemistry -- not downloaded
    'BusinessManagementAccounting-all.bib' => 'Business',
    # N.B. Chemical Engineering; Chemistry -- both not downloaded
    'ComputerScience2008.bib' => 'Computer Science',
    'ComputerScience2014.bib' => 'Computer Science',
    'ComputerScience2018.bib' => 'Computer Science',
    'ComputerScience2021.bib' => 'Computer Science',
    'ComputerScience2024.bib' => 'Computer Science',
    'DecisionSciences.bib' => 'Decision Sciences',
    # N.B. Earth and Planetary Sciences -- not downloaded
    'EconomicsEconometricsFinance.bib' => 'Economics',
    'Energy.bib' => 'Energy',
    'Engineering.2013.bib' => 'Engineering',
    'Engineering.2014-2019.bib' => 'Engineering',
    'Engineering.2015-2020.bib' => 'Engineering',
    'Engineering.2020-2024.bib' => 'Engineering',
    'EnvironmentalScience.bib' => 'Environmental Science',
    # N.B. Immunology and Microbiology -- not downloaded
    # N.B. Materials Science -- not downloaded
    'Mathematics.2015.bib' => 'Mathematics',
    'Mathematics.2024.bib' => 'Mathematics',
    'Medicine.bib' => 'Medicine',
    # N.B. Neuroscience -- not downloaded
    'Nursing.bib' => 'Nursing',
    # N.B. Pharmacology -- not downloaded
    # N.B. Physics and Astronomy -- not downloaded
    'Psychology.bib' => 'Psychology',
    'SocialSciences.bib' => 'Social Sciences',
    # N.B. Veterinary -- not downloaded
    # N.B. Dentistry -- not downloaded
    'HealthProfessions.bib' => 'Health Professions',
    'Undefined.bib' => 'NA'
);

my %comp_sci_scats = (
    'Computer Science' => 1,
    'CS' => 1,
    'Engineering' => 1,
    'Eng' => 1,
    'Mathematics' => 1,
    'Maths' => 1
);

my %soc_sci_scats = (
    'Arts and Humanities' => 1,
    'A&H' => 1,
    'Business' => 1,
    'BM&A' => 1,
    'Decision Sciences' => 1,
    'Decis' => 1,
    'Multidisciplinary' => 1,
    'Multid' => 1,
    'Social Sciences' => 1,
    'Soc' => 1
);

my %short_scats = (
    'Multidisciplinary' => 'Multid',
    'Agricultural and Biological Sciences' => 'Ag Biol',
    'Arts and Humanities' => 'A&H',
    'Business' => 'BM&A',
    'Computer Science' => 'CS',
    'Decision Sciences' => 'Decis',
    'Economics' => 'Econ',
    'Energy' => 'En',
    'Engineering' => 'Eng',
    'Environmental Science', 'Env',
    'Mathematics' => 'Maths',
    'Medicine' => 'Med',
    'Nursing' => 'Nurs',
    'Psychology' => 'Psy',
    'Social Sciences' => 'Soc',
    'Health Professions' => 'Health'
);

sub sort_asjc {
    my ($a, $b) = @_;

    if(exists($soc_sci_scats{$a})) {
        return exists($soc_sci_scats{b}) ? ($a cmp $b) : -1;
    }
    elsif(exists($soc_sci_scats{$b})) {
        return 1;
    }
    elsif(exists($comp_sci_scats{$a})) {
        return exists($comp_sci_scats{$b}) ? ($a cmp $b) : -1;
    }
    elsif(exists($comp_sci_scats{$b})) {
        return 1;
    }
    else {
        return $a cmp $b;
    }
}

my %sw_topics = (
    'Agents.jl' => 0,
    'GAMA' => 0,
    'MASON' => 0,
    'NetLogo' => 0,
    'Repast' => 0,
    'Swarm' => 1,
    'FLAMEGPU' => 0
);

sub sort_topics {
    my ($a, $b) = @_;

    if(exists($sw_topics{$a})) {
        return exists($sw_topics{$b}) ? ($a cmp $b) : -1;
    }
    elsif(exists($sw_topics{$b})) {
        return 1;
    }
    else {
        return $a cmp $b;
    }
}

my %shortj = (
    'ADAPTIVE BEHAVIOUR' => 'Adapt Behav',
    'AGRICULTURAL SYSTEMS' => 'Ag Syst',
    'ARTIFICIAL INTELLIGENCE AND LAW' => 'AI Law',
    'BEHAVIOURAL ECOLOGY' => 'Behav Ecol',
    'COMPUTATIONAL ECONOMICS' => 'Comp Econ',
    'COMPUTERS, ENVIRONMENT AND URBAN SYSTEMS' => 'CEUS',
    'ENERGIES' => 'En',
    'ENVIRONMENTAL MODELLING AND SOFTWARE' => 'EMS',
    'FISCAL STUDIES' => 'Fisc Stud',
    'FOREST ECOLOGY AND MANAGEMENT' => 'For Ecol Mgt',
    'HABITAT INTERNATIONAL' => 'Hab Int',
    'INFORMATION SCIENCES' => 'Info Sci',
    'INTERACTION STUDIES' => 'Inter Stud',
    'INTERNATIONAL JOURNAL OF ENVIRONMENTAL RESEARCH AND PUBLIC HEALTH' => 'IJ Env Res Pub Health',
    'JOURNAL OF APPLIED ECOLOGY' => 'J Appl Ecol',
    'JOURNAL OF ARTIFICIAL SOCIETIES AND SOCIAL SIMULATION' => 'JASSS',
    'JOURNAL OF ASIAN ARCHITECTURE AND BUILDING ENGINEERING' => 'J As Arch Build Eng',
    'JOURNAL OF CONFLICT RESOLUTION' => 'J Conf Resol',
    'JOURNAL OF EUROPEAN SOCIAL POLICY' => 'J Eur Soc Pol',
    'JOURNAL OF MATHEMATICAL SOCIOLOGY' => 'J Math Sociol',
    'JOURNAL OF PROFESSIONAL NURSING' => 'J Prof Nurs',
    'JOURNAL OF SCIENCE EDUCATION AND TECHNOLOGY' => 'J Sci Ed Tech',
    'JOURNALS OF GERONTOLOGY SERIES B-PSYCHOLOGICAL SCIENCES AND SOCIAL SCIENCES' => 'J Geront B',
    'MEDICAL DECISION MAKING' => 'Med Decis Mak',
    'NONLINEAR DYNAMICS PSYCHOLOGY AND LIFE SCIENCES' => 'Nonlin Dyn Psy Life Sci',
    'PERSONALITY AND INDIVIDUAL DIFFERENCES' => 'Person Indiv Diff',
    'PLOS ONE' => 'PLoS 1',
    'SMART INNOVATION, SYSTEMS AND TECHNOLOGIES' => 'SIST',
    'SUSTAINABILITY' => 'Sust',
    'TECHNOLOGICAL FORECASTING AND SOCIAL CHANGE' => 'Tech Fore Soc Ch',
    'TRANSPORTATION RESEARCH PART F-TRAFFIC PSYCHOLOGY AND BEHAVIOUR' => 'Trans Res F',
    'TRANSPORTATION RESEARCH RECORD' => 'Trans Res Rec',
    'TRENDS IN ORGANIZED CRIME' => 'Trend Org Crim'
);

my %journal_subs = (
    'JASSS' => 'JOURNAL OF ARTIFICIAL SOCIETIES AND SOCIAL SIMULATION',
    'JASSS-THE JOURNAL OF ARTIFICIAL SOCIETIES AND SOCIAL SIMULATION' =>
        'JOURNAL OF ARTIFICIAL SOCIETIES AND SOCIAL SIMULATION',
    'SUSTAINABILITY SWITZERLAND' => 'SUSTAINABILITY',
    'SUSTAINABILITY (SWITZERLAND)' => 'SUSTAINABILITY',
    'ENVIRONMENTAL MODELLING SOFTWARE' => 'ENVIRONMENTAL MODELLING AND SOFTWARE',
    'ENVIRONMENTAL MODELLING & SOFTWARE' => 'ENVIRONMENTAL MODELLING AND SOFTWARE',
    'ENVIRONMENTAL MODELLING \& SOFTWARE' => 'ENVIRONMENTAL MODELLING AND SOFTWARE',
    'THE JOURNAL OF MATHEMATICAL SOCIOLOGY' => 'JOURNAL OF MATHEMATICAL SOCIOLOGY',
    'COMPUTERS ENVIRONMENT AND URBAN SYSTEMS' => 'COMPUTERS, ENVIRONMENT AND URBAN SYSTEMS',
    'SMART INNOVATION SYSTEMS AND TECHNOLOGIES' => 'SMART INNOVATION, SYSTEMS AND TECHNOLOGIES',
    'ADAPTIVE BEHAVIOR' => 'ADAPTIVE BEHAVIOUR',
    'BEHAVIORAL ECOLOGY' => 'BEHAVIOURAL ECOLOGY',
    'TRANSPORTATION RESEARCH PART F TRAFFIC PSYCHOLOGY AND BEHAVIOUR' =>
        'TRANSPORTATION RESEARCH PART F-TRAFFIC PSYCHOLOGY AND BEHAVIOUR',
    'JOURNALS OF GERONTOLOGY SERIES B PSYCHOLOGICAL SCIENCES AND SOCIAL SCIENCES' =>
        'JOURNALS OF GERONTOLOGY SERIES B-PSYCHOLOGICAL SCIENCES AND SOCIAL SCIENCES'
);

my %abbrevj = (                 # Any journal title abbreviation not just selected
    'LECTURE NOTES IN ARTIFICIAL INTELLIGENCE' => 'LNAI',
    'LECTURE NOTES IN ARTIFICIAL INTELLIGENCE '.
        '(SUBSERIES OF LECTURE NOTES IN COMPUTER SCIENCE)' => 'LNAI',
    'LECTURE NOTES IN COMPUTER SCIENCE' => 'LNCS',
    'LECTURE NOTES IN COMPUTER SCIENCE '.
        '(INCLUDING SUBSERIES LECTURE NOTES IN ARTIFICIAL INTELLIGENCE '.
        'AND LECTURE NOTES IN BIOINFORMATICS)' => 'LNCS',
    '10TH INTERNATIONAL CONFERENCE ON AUTONOMOUS AGENTS AND '.
        'MULTIAGENT SYSTEMS 2011, AAMAS 2011' => 'AAMAS 2011',
    '11TH INTERNATIONAL CONFERENCE ON AUTONOMOUS AGENTS AND '.
        'MULTIAGENT SYSTEMS 2012, AAMAS 2012: INNOVATIVE '.
        'APPLICATIONS TRACK' => 'AAMAS 2012',
    '12TH INTERNATIONAL CONFERENCE ON AUTONOMOUS AGENTS AND '.
        'MULTIAGENT SYSTEMS 2013, AAMAS 2013' => 'AAMAS 2013',
    '13TH INTERNATIONAL CONFERENCE ON AUTONOMOUS AGENTS AND '.
        'MULTIAGENT SYSTEMS, AAMAS 2014' => 'AAMAS 2014',
    'AAMAS\'14: PROCEEDINGS OF THE 2014 INTERNATIONAL '.
        'CONFERENCE ON AUTONOMOUS AGENTS & MULTIAGENT SYSTEMS' => 'AAMAS 2014',
    'PROCEEDINGS OF THE 2015 INTERNATIONAL CONFERENCE '.
        'ON AUTONOMOUS AGENTS & MULTIAGENT SYSTEMS (AAMAS\'15)' => 'AAMAS 2015',
    'AAMAS\'16: PROCEEDINGS OF THE 2016 INTERNATIONAL '.
        'CONFERENCE ON AUTONOMOUS AGENTS & MULTIAGENT SYSTEMS' => 'AAMAS 2016',
    'AAMAS\'17: PROCEEDINGS OF THE 16TH INTERNATIONAL '.
        'CONFERENCE ON AUTONOMOUS AGENTS AND MULTIAGENT SYSTEMS' => 'AAMAS 2017',
    'PROCEEDINGS OF THE 17TH INTERNATIONAL CONFERENCE '.
        'ON AUTONOMOUS AGENTS AND MULTIAGENT SYSTEMS (AAMAS\' 18)' => 'AAMAS 2018',
    'AAMAS `19: PROCEEDINGS OF THE 18TH INTERNATIONAL '.
        'CONFERENCE ON AUTONOMOUS AGENTS AND MULTIAGENT SYSTEMS' => 'AAMAS 2019',
    'PROCEEDINGS OF THE INTERNATIONAL JOINT CONFERENCE ON AUTONOMOUS '.
        'AGENTS AND MULTIAGENT SYSTEMS, AAMAS' => 'AAMAS', 
    'PROCEEDINGS OF THE THIRD INTERNATIONAL JOINT CONFERENCE '.
        'ON AUTONOMOUS AGENTS AND MULTIAGENT SYSTEMS, AAMAS 2004' => 'AAMAS 2004',
    'PROCEEDINGS OF THE 23RD AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2008' => 'AAAI 2008',
    'PROCEEDINGS OF THE 24TH AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2010' => 'AAAI 2010',
    'PROCEEDINGS OF THE 25TH AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2011' => 'AAAI 2011',
    'PROCEEDINGS OF THE 26TH AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2012' => 'AAAI 2012',
    'PROCEEDINGS OF THE 27TH AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2013' => 'AAAI 2013',
    'PROCEEDINGS OF THE TWENTY-EIGHTH AAAI CONFERENCE ON '.
        'ARTIFICIAL INTELLIGENCE' => 'AAAI 2014',
    'PROCEEDINGS OF THE TWENTY-NINTH AAAI CONFERENCE ON '.
        'ARTIFICIAL INTELLIGENCE' => 'AAAI 2015',
    '30TH AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE, AAAI 2016' => 'AAAI 2016',
    'THIRTIETH AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE' => 'AAAI 2016',
    '31ST AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE, AAAI 2017' => 'AAAI 2017',
    'THIRTY-FIRST AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE' => 'AAAI 2017',
    '32ND AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE, AAAI 2018' => 'AAAI 2018',
    'AAAI 2020 - 34TH AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE' => 'AAAI 2020',
    '35TH AAAI CONFERENCE ON ARTIFICIAL INTELLIGENCE, AAAI 2021' => 'AAAI 2021',
    'PROCEEDINGS OF THE 36TH AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2022' => 'AAAI 2022',
    'PROCEEDINGS OF THE 37TH AAAI CONFERENCE ON ARTIFICIAL '.
        'INTELLIGENCE, AAAI 2023' => 'AAAI 2023',
    'CONFERENCE PROCEEDINGS - 6TH CONFERENCE OF THE EUROPEAN '.
        'SOCIAL SIMULATION ASSOCIATION, ESSA 2009' => 'ESSA 2009',
    'PROCEEDINGS OF THE 4TH CONFERENCE OF THE EUROPEAN SOCIAL '.
        'SIMULATION ASSOCIATION, ESSA 2007' => 'ESSA 2007',
    'ADVANCES IN SOCIAL SIMULATION 2015' => 'ESSA 2015',
    'ADVANCES IN SOCIAL SIMULATION' => 'ESSA',
    'ADVANCING SOCIAL SIMULATION: THE FIRST WORLD CONGRESS' => 'ESSA 2006',
    'MULTI-AGENT BASED SIMULATION XVIII, MABS 2017' => 'MABS 2017',
    'MULTI-AGENT-BASED SIMULATION XXIII, MABS 2022' => 'MABS 2022',
    'MODSIM 2007: INTERNATIONAL CONGRESS ON MODELLING AND SIMULATION: '.
        'LAND, WATER AND ENVIRONMENTAL MANAGEMENT: INTEGRATED SYSTEMS '.
        'FOR SUSTAINABILITY' => 'MODSIM 2007',
    'MODSIM 2003: INTERNATIONAL CONGRESS ON MODELLING AND SIMULATION, '.
        'VOLS 1-4: VOL 1: NATURAL SYSTEMS, PT 1; VOL 2: NATURAL SYSTEMS, '.
        'PT 2; VOL 3: SOCIO-ECONOMIC SYSTEMS; VOL 4: GENERAL SYSTEMS' => 
        'MODSIM 2007',
    'AGENT AND MULTI-AGENT SYSTEMS: TECHNOLOGIES AND APPLICATIONS, '.
        'PROCEEDINGS' => 'AMSTA',
    '2015 WINTER SIMULATION CONFERENCE (WSC)' => 'WSC 2015',
    'MICROSIMULATION IN GOVERNMENT POLICY AND FORECASTING' =>
        'Microsim in Gov Policy & Forecasting',
    '5TH INTERNATIONAL CONFERENCE ON AMBIENT SYSTEMS, NETWORKS AND '.
        'TECHNOLOGIES (ANT-2014), THE 4TH INTERNATIONAL CONFERENCE ON '.
        'SUSTAINABLE ENERGY INFORMATION TECHNOLOGY (SEIT-2014)' => 'ANT/SEIT 2014',
    'AGENT-BASED APPROACHES IN ECONOMIC AND SOCIAL COMPLEX SYSTEMS VIII' =>
        'AESCS',
    'PROCEEDINGS OF THE 13TH INTERNATIONAL CONFERENCE ON INDUSTRIAL '.
        'ENGINEERING AND ENGINEERING MANAGEMENT, VOLS 1-5: INDUSTRIAL '.
        'ENGINEERING AND MANAGEMENT INNOVATION IN NEW-ERA' => 'IEEM',
    'PROCEEDINGS OF THE 38TH CHINESE CONTROL CONFERENCE (CCC)' => 'CCC',
    'MICROSIMULATION AND PUBLIC POLICY' => 'Microsim & Pub Policy',
    'SIMULATING INTERACTING AGENTS AND SOCIAL PHENOMENA: THE SECOND WORLD '.
        'CONGRESS' => 'SIASP',
    'ENVIRONMENT AND PLANNING A-ECONOMY AND SPACE' => 'Env Plan A',
    'ENVIRONMENT AND PLANNING A' => 'Env Plan A',
    'ENVIRONMENT AND PLANNING B-URBAN ANALYTICS AND CITY SCIENCE' => 'Env Plan B',
    'ENVIRONMENT AND PLANNING B-PLANNING \& DESIGN' => 'Env Plan B',
    'ENVIRONMENT AND PLANNING C-GOVERNMENT AND POLICY' => 'Env Plan C',
    'PROCEEDINGS OF THE IEEE CONFERENCE ON DECISION AND CONTROL' => 'Proc IEEE Decis Ctrl',
    'AGENT-BASED APPROACHES IN ECONOMIC AND SOCIAL COMPLEX SYSTEMS IV'
        => 'Agent-Based Approaches in Economic and Social Complex Systems IV',
    'CONSTRUCTION RESEARCH CONGRESS 2016: OLD AND NEW CONSTRUCTION TECHNOLOGIES CONVERGE '
        .'IN HISTORIC SAN JUAN' => 'Construction Research Congress 2016',
    'ELEMENTARY ENGLISH' => 'Elementary English',
);
while(my ($key, $value) = each(%shortj)) {
    $abbrevj{$key} = $value;
}

my %citekeys;           # Citekey set
my %doi_cite;           # DOI to citekey
my %bibtex_entries = (
    "article" => ["__author", "title", "journal", "year", "volume", "number", "__pages"],
    "book" => ["__author", "title", "publisher", "address", "year"],
    "booklet" => ["title", "author", "howpublished", "month", "year"],
    "inbook" => ["__author", "title", "booktitle", "year", "publisher", "address", "__pages"],
    "incollection" => ["__author", "editor", "title", "booktitle", "year", "publisher", "address", "__pages"],
    "inproceedings" => ["__author", "title", "booktitle", "series", "year", "__pages", "publisher", "address"],
    "manual" => ["title", "__author", "organization", "address", "year"],
    "mastersthesis" => ["__author", "title", "school", "year", "address", "month"],
    "misc" => ["title", "__author", "howpublished", "year"],
    "phdthesis" => ["__author", "title", "school", "address", "year", "year", "month"],
    "proceedings" => ["editor", "title", "series", "volume", "publisher", "address", "year"],
    "techreport" => ["title", "__author", "institution", "address", "number", "year", "month"],
    "author" => ["__author", "title", "year"]
);

my %bibtex_defaults = (
    "author" => "Anon",
    "title" => "(Untitled)",
    "year" => "no date",
);

my @stages = ("download", "filter", "journal", "screen", "review", "result");
my @stage_titles = ("Downloaded", "Filtered", "Journal", "Screened", "Reviewed", "Included");

my $ST_DOWNLOAD = 0;
my $ST_FILTER = 1;
my $ST_JOURNAL = 2;
my $ST_SCREEN = 3;
my $ST_REVIEW = 4;
my $ST_RESULT = 5;

################################################################################
#                                                                              #
#  ####  ###  #   # #   #  ###  #   # ####        #      ###  #   # #####      #
# #     #   # ## ## ## ## #   # ##  # #   #       #       #   ##  # #          #
# #     #   # # # # # # # ##### # # # #   #       #       #   # # # ####       #
# #     #   # #   # #   # #   # #  ## #   #       #       #   #  ## #          #
#  ####  ###  #   # #   # #   # #   # ####        #####  ###  #   # #####      #
#                                                                              #
################################################################################

while(scalar(@ARGV) > 0 && substr($ARGV[0], 0, 1) eq '-') {
    my $opt = shift(@ARGV);
    if($opt eq '--help' || $opt eq '-h') {
        die "Usage: $0 [--no-R] [--log <file>] [--pdf <key> <pdf-file>] ",
            "[--param <key> <value>] [--input <key> <file>] [--output <key> <file>]\n";
    }
    elsif($opt eq '--no-R' || $opt eq '-R') {
        $Rcmd = "";
    }
    elsif($opt eq '--no-cloud') {
        $parameters{'R-do-cloud'} = 0;
    }
    elsif($opt eq '--no-sankey') {
        $parameters{'R-do-sankey'} = 0;
    }
    elsif($opt eq '--no-table-mi') {
        $parameters{'R-do-table-mi'} = 0;
    }
    elsif($opt =~ /^--no-(.*)$/) {
        my $param_key = $1;
        if(exists($parameters{$param_key}) && exists($boolean_param{$param_key})) {
            $parameters{$param_key} = 0;
        }
        else {
            die "Unrecognized boolean parameter: $param_key\n";
        }
    }
    elsif($opt =~ /^--with-(.*)$/) {
        my $param_key = $1;
        if(exists($parameters{$param_key}) && exists($boolean_param{$param_key})) {
            $parameters{$param_key} = 1;
        }
        else {
            die "Unrecognized boolean parameter: $param_key\n";
        }
    }
    elsif($opt eq '--log' || $opt eq '-l') {
        $logfile = shift(@ARGV);
    }
    elsif($opt eq '--pdf' || $opt eq '-f}') {
        my $pdf_key = shift(@ARGV);
        if(exists($pdf_files{$pdf_key})) {
            $pdf_files{$pdf_key} = shift(@ARGV);
        }
        else {
            die "Unrecognized PDF key: $pdf_key\n";
        }
    }
    elsif($opt eq '--param' || $opt eq '--parameter'|| $opt eq '-p') {
        my $param_key = shift(@ARGV);
        if(exists($parameters{$param_key})) {
            $parameters{$param_key} = shift(@ARGV);
        }
        else {
            die "Unrecognized parameter: $param_key\n";
        }
    }
    elsif($opt eq '--input' || $opt eq '-i') {
        my $input_key = shift(@ARGV);
        if(exists($input_files{$input_key})) {
            $input_files{$input_key} = shift(@ARGV);
        }
        else {
            die "Unrecognized input file: $input_key\n";
        }
    }
    elsif($opt eq '--output' || $opt eq '-o') {
        my $output_key = shift(@ARGV);
        if(exists($output_files{$output_key})) {
            $output_files{$output_key} = shift(@ARGV);
        }
        else {
            die "Unrecognized output file: $output_key\n";
        }
    }
    else {
        die "Unrecognized option \"$opt\" -- use $0 --help for usage\n";
    }
}

if(-e $parameters{'output-dir'} && !$parameters{'R-overwrite'}) {
    die "Output directory \"", $parameters{'output-dir'}, "\" exists and not overwriting!\n";
}
if(-e $parameters{'output-dir'} && !-d $parameters{'output-dir'}) {
    die "Output directory \"", $parameters{'output-dir'}, "\" exists, but is not a directory\n";
}
if(!-e $parameters{'output-dir'}) {
    mkdir(0777, $parameters{'output-dir'}) or die "Cannot create output directory \"",
        $parameters{'output-dir'}, "\": $!\n";
}
foreach my $file (keys(%output_files)) {
    next if($file !~ /^R-/);
    if($output_files{$file} !~ /\//) {
        if($output_files{$file} =~ /\.tex$/) {
            $output_files{$file} = $parameters{'tex-dir'}."/".$output_files{$file};
        }
        $output_files{$file} = $parameters{'output-dir'}."/".$output_files{$file};
    }
}
foreach my $file ('bibtex', 'merge-output', 'dodgy-dois') {
    if($input_files{$file} !~ /\//) {
        $input_files{$file} = $parameters{'merge-dir'}."/".$input_files{$file};
    }
}

warn "PROGRESS [", &iso_date(), "]: Processed command line\n";

################################################################################
#                                                                              #
#  ####  ###  #   # #   # #####  #### #####       #####  ###        ####       #
# #     #   # ##  # ##  # #     #       #           #   #   #       #   #      #
# #     #   # # # # # # # ####  #       #           #   #   #       ####       #
# #     #   # #  ## #  ## #     #       #           #   #   #       #   #      #
#  ####  ###  #   # #   # #####  ####   #           #    ###        #   #      #
#                                                                              #
################################################################################

push(@R_LIBS, "networkD3", "htmlwidgets") if($parameters{'R-do-sankey'});
push(@R_LIBS, "wordcloud2", "htmltools") if($parameters{'R-do-cloud'});

if($Rcmd ne "") {
    if(open($R_FP, "|-", $Rcmd)) {
        my $default_fh = select($R_FP);
        $| = 1;             # Make $R_FP unbuffered
        select($default_fh);
        &r_print_globals($R_FP, 0, \%output_files, \%parameters, \%pdf_files);
    }
    else {
        warn "Saving R script to ", $output_files{'R-script'},
            "as cannot connect to R command $Rcmd: $!\n";
        $Rcmd = "";
    }
}
if($Rcmd eq "") {
    # NOT elsif because we might set $Rcmd to "" if we cannot
    # open a connection to R
    open($R_FP, ">", $output_files{'R-script'})
        or die "Cannot create R script ", $output_files{'R-script'}, ": $!\n";
    print $R_FP "#!/usr/bin/env Rscript\n";
    &r_print_globals($R_FP, 1, \%output_files, \%parameters, \%pdf_files);
}

print $R_FP "library(", join(")\nlibrary(", @R_LIBS), ")\n";

&r_print_func($R_FP);

warn "PROGRESS [", &iso_date(), "]: Connected to R ",
    ($Rcmd eq "" ? "via script at ".$output_files{'R-script'} : "via pipe"), "\n";

################################################################################
#                                                                              #
# ####  #####  ###  ####         ###  #   # ####  #   # #####                  #
# #   # #     #   # #   #         #   ##  # #   # #   #   #                    #
# ####  ####  ##### #   #         #   # # # ####  #   #   #                    #
# #   # #     #   # #   #         #   #  ## #     #   #   #                    #
# #   # ##### #   # ####         ###  #   # #      ###    #                    #
#                                                                              #
# #####  ###  #     #####  ####                                                #
# #       #   #     #     #                                                    #
# ####    #   #     ####   ###                                                 #
# #       #   #     #         #                                                #
# #      ###  ##### ##### ####                                                 #
#                                                                              #
################################################################################

# Three problems:
#
# Some Scopus records are getting added _twice_. (Same _filename, same _line)
#   + CHECK LOGIC WHEN ADDING SCOPUS RECORDS
#

&read_dodgy_dois($input_files{'dodgy-dois'}, \%dodgy_dois);

my @db = &read_bibtex($input_files{'bibtex'}, \%index, \%biblio, \%dodgy_dois);
warn "PROGRESS [", &iso_date(), "]: Read ", scalar(@db), " records from ",
    $input_files{'bibtex'}, "\n";

&logbook("Rejected records: ", $missing_field_counts{'_any_field'});
foreach my $field (sort {$a cmp $b} keys(%missing_field_counts)) {
    next if($field eq '_any_field');
    &logbook("\tMissing \"$field\": ", $missing_field_counts{$field});
}

&save_index("bibtex/slr-index.csv", \%index);

my @corpus = &read_corpus($input_files{'corpus'});

warn "PROGRESS [", &iso_date(), ']: Read ', scalar(@corpus), " corpus records ",
    "from ", $input_files{'corpus'}, "\n";

my @screen = &read_screened($input_files{'screen'});

warn "PROGRESS [", &iso_date(), "]: Read ", scalar(@screen), " records for ",
    "screening from ", $input_files{'screen'}, "\n";

my @scrres = &read_screening($input_files{'screen-results'});

warn "PROGRESS [", &iso_date(), "]: Read ", scalar(@scrres), " screening ",
    "results records from ", $input_files{'screen-results'}, "\n";

my @assign = &read_assignments($input_files{'review-assign'});

warn "PROGRESS [", &iso_date(), "]: Read ", scalar(@assign), " paper review ",
    "assignments from ", $input_files{'review-assign'}, "\n";

my @review = &read_reviews($input_files{'review'}, \%google_form, \%reviewers);

warn "PROGRESS [", &iso_date(), "]: Read ", scalar(@review), " review results ",
    "from ", $input_files{'review'}, "\n";

################################################################################
#                                                                              #
#  #### ####   ###   ####  ####       #   #  ###  #####  #### #   #            #
# #     #   # #   # #     #           ## ## #   #   #   #     #   #            #
# #     ####  #   #  ###   ###        # # # #####   #   #     #####            #
# #     #   # #   #     #     #       #   # #   #   #   #     #   #            #
#  #### #   #  ###  ####  ####        #   # #   #   #    #### #   #            #
#                                                                              #
# ##### #   # ##### ####   ###  #####  ####                                    #
# #     ##  #   #   #   #   #   #     #                                        #
# ####  # # #   #   ####    #   ####   ###                                     #
# #     #  ##   #   #   #   #   #         #                                    #
# ##### #   #   #   #   #  ###  ##### ####                                     #
#                                                                              #
################################################################################

# N.B. There are various reasons why we might not be able to match up records
# using the indexes. The most significant will have been the original corpuses
# not necessarily having told Perl to read UTF-8 bibtex data. This will lead to
# &orig_text() not exactly reproducing whatever title or journal was used for
# the MD5, for example. The same kind of problem will cause title and abstract
# indexes to fail.

my @lost_corpus = &lookup_db(\@corpus, \@db, \%index, \%db2corpus, \%corpus2db,
    "corpus", 1);
&logbook("Matched ", (scalar(@corpus) - scalar(@lost_corpus)),
    " of ", scalar(@corpus), " papers in corpus to BibTeX");
if(scalar(@lost_corpus) > 0) {
    &report_lookup_usage("corpus");
}

my @lost_screen = &lookup_db(\@screen, \@db, \%index, \%db2screen, \%screen2db,
    "screen", 1);
&logbook("Matched ", (scalar(@screen) - scalar(@lost_screen)),
    " of ", scalar(@screen), " papers in screen to BibTeX");
if(scalar(@lost_screen) > 0) {
    &report_lookup_usage("screen");
}
my %scrid_index;
my $n_screen_doi_dup = 0;
my $n_screen_doi_err = 0;
my $n_screen_doi_nil = 0;
my $n_screen_md5_dup = 0;
my $n_screen_md5_ttl = 0;
my $n_screen_md5_neq = 0;
my $n_screen_md5_deja_vu = 0;
my $n_screen_md5_add = 0;
my $n_screen_no_id = 0;
for(my $i = 0; $i <= $#screen; $i++) {
    my $data = $screen[$i];
    my $doi = $$data[$R_DOI];
    my $md5 = $$data[$R_MD5];

    if(!exists($screen2db{$i})) {
        &logbook("Screen paper ", ($i + 1), " with DOI \"$doi\" and MD5 \"$md5\" ",
            "does not have an index to look up in the database\n");
        next;
    }
    my $paper = $db[$screen2db{$i}];

    if($doi =~ /\//) {
        if(exists($scrid_index{$doi})) {
            &logbook("Screen file has duplicated DOI $doi at paper ", ($i + 1),
                " -- previous paper ", (1 + $scrid_index{$doi}));
            $n_screen_doi_dup++;
        }
        else {
            $scrid_index{$doi} = $i;

            if(exists($paper->{'doi'})) {
                if(lc($paper->{'doi'}) ne lc($doi)) {
                    &logbook("Screen file DOI $doi mapped to paper in database with DOI ",
                        $paper->{'doi'});
                    $n_screen_doi_err++;
                }
            }
            else {
                &logbook("Screen file DOI $doi mapped to paper in database with no DOI");
                $n_screen_doi_nil++;
            }
        }
    }
    elsif($md5 =~ /^[0-9a-f]+$/) {
        if(exists($scrid_index{$md5})) {
            &logbook("Screen file has duplicated MD5 $md5 at paper ", ($i + 1),
                " -- previous paper ", (1 + $scrid_index{$md5}));
            $n_screen_md5_dup++;
        }
        else {
            $scrid_index{$md5} = $i;

            my $n_eq = 0;
            my @keys;
            foreach my $md5_key ('__md5', '_wos__md5', '_scopus__md5') {
                if(exists($paper->{$md5_key})) {
                    if($paper->{$md5_key} ne $md5) {
                        push(@keys, "$md5_key = ".($paper->{$md5_key}));
                    }
                    else {
                        $n_eq++;
                    }
                }
            }
            if(scalar(@keys) > 0) {
                if($n_eq == 0) {
                    if($$data[$R_JNL] eq $paper->{'__source'} && uc($$data[$R_TTL]) eq uc($paper->{'title'})) {
                        $n_screen_md5_ttl++;
                    }
                    else {
                        &logbook("Screen file MD5 $md5 not equal to ", join("; ", @keys));
                        &logbook("\tScreen file title and journal: ",
                            $$data[$R_TTL], " ", $$data[$R_JNL]);
                        &logbook("\tDatabase title and journal: ",
                            $paper->{'title'}, " ", $paper->{'__source'});
                        $n_screen_md5_neq++;
                    }
                }

                if(exists($ix_md5{$md5})) {
                    &logbook("There is a paper in the database with MD5 $md5 that isn't ",
                        "the one screen file entry ", ($i + 1), " has been matched to!");
                    $n_screen_md5_deja_vu++;
                }
                else {
                    $ix_md5{$md5}->{$screen2db{$i}}++;
                    $n_screen_md5_add++;
                }
            }
        }
    }
    else {
        &logbook("Screen file entry ", ($i + 1), " has no DOI or MD5");
        $n_screen_no_id++;
    }
}

&logbook("#", ("#" x 70));
&logbook("Screen file match check summary:");
&logbook("  + Number of entries in the screen file with no DOI or MD5:       $n_screen_no_id");
&logbook("  + Number of duplicated DOI entries in the screen file:           $n_screen_doi_dup");
&logbook("  + Number of duplicated MD5 entries in the screen file:           $n_screen_md5_dup");
&logbook("  + Number of DOI entries in the screen file matched to a paper in");
&logbook("    the database with no DOI:                                      $n_screen_doi_nil");
&logbook("  + Number of DOI entries in the screen file matched to a paper in");
&logbook("    the database with a different DOI:                             $n_screen_doi_err");
&logbook("  + Number of new MD5 indexes added because matched paper in the");
&logbook("    database had one or more different MD5s:                       $n_screen_md5_add");
&logbook("  + Number of new MD5 indexes not added because a paper in the");
&logbook("    database already had that MD5:                                 $n_screen_md5_deja_vu");
&logbook("  + Number of MD5 entries in the screen file that were not equal to");
&logbook("    any of their matched database entry MD5s due to title case:    $n_screen_md5_ttl");
&logbook("  + Number of MD5 entries not equal for a different reason:        $n_screen_md5_neq");
&logbook("#", ("#" x 70));

my @lost_scrres = &lookup_screen(\@scrres, "screening results", \%scrid_index,
    \%screen2db, \%scrres2db, \%db2scrres, 0..$#scrres);
if(scalar(@lost_scrres) > 0) {
    &logbook("There were ", scalar(@lost_scrres), " papers in the screening ",
        "results that could not be matched to the screening file:");
    foreach my $ix (@lost_scrres) {
        &logbook("\tScreening result ", ($ix + 1), ": DOI \"",
            $scrres[$ix]->[$R_DOI], "\"; MD5 \"",
            $scrres[$ix]->[$R_MD5], "\"");
    }
}
else {
    &logbook("All screening results have been matched to their corresponding ",
        "screen file entry");
}

my @lost_assign = &lookup_screen(\@assign, "review assignments", \%scrid_index,
    \%screen2db, \%assign2db, \%db2assign, 0..$#assign);
if(scalar(@lost_assign) > 0) {
    &logbook("There were ", scalar(@lost_assign), " papers in the review ",
        "assignments that could not be matched to the screening file");

    foreach my $ix (@lost_assign) {
        &logbook("\tReview assignment ", ($ix + 1), ": DOI \"",
            $assign[$ix]->[$A_DOI], "\"; MD5 \"",
            $assign[$ix]->[$A_MD5], "\"");
    }
}
else {
    &logbook("All review assignments have been matched to their corresponding ",
        "screen file entry");
}

&match_reviews(\@assign, \@review, \%rev2ass, \%assign2db, \@db);
my @merged = &merge_reviews(\@assign, \@review, \%assign2db, \%db2merged, \%merged2db);

&logbook("There are ", scalar(@screen), " screening papers linked to ",
    scalar(keys(%db2screen)), " unique BibTeX entries");
&logbook("There are ", scalar(@scrres), " screening results papers linked to ",
    scalar(keys(%db2scrres)), " unique BibTeX entries");
&logbook("There are ", scalar(@assign), " review assignments linked to ",
    scalar(keys(%db2assign)), " unique BibTeX entries");
&logbook("There are ", scalar(@merged), " merged reviews linked to ",
    scalar(keys(%db2merged)), " unique BibTeX entries");

warn "PROGRESS [", &iso_date(), "]: Cross-matched BibTeX, corpus, screening, ",
    "screening results, review assignments and review results\n";

################################################################################
#                                                                              #
#  #### #   # #   # #   #  ###  ####   ###  ##### #####                        #
# #     #   # ## ## ## ## #   # #   #   #      #  #                            #
#  ###  #   # # # # # # # ##### ####    #     #   ####                         #
#     # #   # #   # #   # #   # #   #   #    #    #                            #
# ####   ###  #   # #   # #   # #   #  ###  ##### #####                        #
#                                                                              #
#  ####  #### ####  ##### ##### #   #  ###  #   #  ####                        #
# #     #     #   # #     #     ##  #   #   ##  # #                            #
#  ###  #     ####  ####  ####  # # #   #   # # # #  ##                        #
#     # #     #   # #     #     #  ##   #   #  ## #   #                        #
# ####   #### #   # ##### ##### #   #  ###  #   #  ####                        #
#                                                                              #
################################################################################

#  1. Summarize the downloaded articles' topic search. Since this requires
#     going through all the papers in the database, which takes ages, a lot
#     of the preparatory work here also sets up the data structures needed
#     for subsequent analyses.

my ($n_no_topic, $n_no_topic_intent) = &assign_topics(\@db);
warn "PROGRESS [", &iso_date(), "]: Assigned topics to ", scalar(@db), " papers ",
    "in the BibTeX database\n";

&logbook("Of ", scalar(@db), " papers in the BibTeX database, $n_no_topic ",
    "had no topic, and $n_no_topic_intent had no topic as the search was ",
    "originally intended");
my (%n_corpora_topic, %n_corpora_topic_intent, %n_corpora);
my (%topic_links, %topic_intent_links);
my %all_topics;     # {as searched topic} -> number of papers
my %asjc_n;         # {ASJC category} -> number of papers
my %asjc_links;     # Used for building ASJC Sankey diagram
my %asjc_stage;     # Used for building ASJC Sankey diagram
my %paper_links;    # Used for building ASJC Sankey diagram
my %wos_asjc;       # {WoS cat} -> {ASJC cat} -> number of co-occurrences
my %wos_stage;      # Used for building WoS Sankey diagram
my %src_wos;        # {__source} -> {WoS category} -> number of papers
my %src_any_wos;    # {__source} -> number of papers with any screened WoS category
                    # (N.B. Built later once we have found out what these are)
my %src_asjc;       # {__source} -> {ASJC category} -> number of papers
my %src_n;          # {__source} -> number of papers
my %src_sr_n;       # {__source} -> {S1|S2|S3|R1|R2|R3|R4} -> number of papers
                    # rejected for the given reason
my %wos_n;          # {WoS category} -> number of papers
my %asjc_asjc_n;    # {ASJC cat} -> {ASJC cat} -> n. papers confusion matrix
my %wos_wos_n;      # {WoS cat} -> {WoS cat} -> n. papers confusion matrix
my %wos_asjc_n;     # {WoS cat} -> {ASJC cat} -> n. papers _with valid DOI_
my %stat_src_wos;   # {stage} -> {_src} -> {WoS cat} -> n. papers
my %stat_src_asjc;  # {stage} -> {_src} -> {ASJC cat} -> n. papers
my %stat_src_n;     # {stage} -> {_src} -> n.papers
my %stat_asjc_n;    # {stage} -> {ASJC cat} -> n. papers
my %stat_wos_n;     # {stage} -> {WoS cat} -> n. papers
my %stat_n;         # {stage} -> n.papers

##############################################################################
# Loop through the whole database and extract various usage counts
##############################################################################

my $progress_time = time();
for(my $i = 0; $i <= $#db; $i++) {
    if(time() - $progress_time > $parameters{'R-progress-interval'}) {
        warn "Progress [", &iso_date(), "]: Processed ", ($i + 1), " of ",
            ($#db + 1), " records\n";
        $progress_time = time();
    }

    my @stage_ck = ($ST_DOWNLOAD);
    # Was this paper screened?
    push(@stage_ck, $ST_SCREEN) if(exists($db2screen{$i}));
    
    # Was it reviewed?
    push(@stage_ck, $ST_REVIEW) if(exists($db2assign{$i}));

    # Was it in the merged results?
    push(@stage_ck, $ST_RESULT) if(exists($db2merged{$i}));

    # Count topics as searched and topics as intended
    my @topic_list = keys(%{$db[$i]->{'__topics'}});
    my @topic_intent_list = keys(%{$db[$i]->{'__topics_intent'}});
    my $n_topic = scalar(@topic_list);
    my $n_topic_intent = scalar(@topic_intent_list);
    foreach my $topic (@topic_list) {
        $all_topics{$topic}++;
    }

    # Count ASJC categories
    my @asjc_list;
    foreach my $asjc_cat (keys(%{$db[$i]->{'__asjc_cat'}})) {
        if(exists($short_scats{$asjc_cat})) {
            push(@asjc_list, $asjc_cat);
        }
        else {
            die "Category $asjc_cat not found\n";
        }
    }
    @asjc_list = sort {$a cmp $b} @asjc_list;
    if(scalar(@asjc_list) == 0) {
        push(@asjc_list, '(None)');
    }
    else {
        for(my $i = 0; $i < $#asjc_list; $i++) {
            for(my $j = $i + 1; $j <= $#asjc_list; $j++) {
                $asjc_asjc_n{$asjc_list[$i]}->{$asjc_list[$j]}++;
            }
        }
    }
    foreach my $asjc_cat (@asjc_list) {
        $asjc_n{$asjc_cat}++;
        $src_asjc{$db[$i]->{'__source'}}->{$asjc_cat}++;
        $asjc_stage{$stages[$ST_DOWNLOAD]}->{$asjc_cat}++;
        foreach my $stg_ix (@stage_ck) {
            $stat_src_asjc{$stages[$stg_ix]}->{$db[$i]->{'__source'}}->{$asjc_cat}++;
            $stat_asjc_n{$stages[$stg_ix]}->{$asjc_cat}++;
        }
    }

    # Count WoS categories
    my @wos_list;
    foreach my $wos_cat (keys(%{$db[$i]->{'__wos_cat'}})) {
        $src_wos{$db[$i]->{'__source'}}->{$wos_cat}++;
        $wos_n{$wos_cat}++;
        foreach my $stg_ix (@stage_ck) {
            $stat_src_wos{$stages[$stg_ix]}->{$db[$i]->{'__source'}}->{$wos_cat}++;
            $stat_wos_n{$stages[$stg_ix]}->{$wos_cat}++;
        }

        foreach my $asjc_cat (@asjc_list) {
            $wos_asjc{$wos_cat}->{$asjc_cat}++;
        }
        $wos_stage{$stages[$ST_DOWNLOAD]}->{$wos_cat}++;
        push(@wos_list, $wos_cat);
    }
    @wos_list = sort {$a cmp $b} @wos_list;
    for(my $i = 0; $i < $#wos_list; $i++) {
        for(my $j = $i + 1; $j <= $#wos_list; $j++) {
            $wos_wos_n{$wos_list[$i]}->{$wos_list[$j]}++;
        }
        if(exists($db[$i]->{'doi'})) {
            my $doi = $db[$i]->{'doi'};
            if(!exists($dodgy_dois{$doi})) {
                foreach my $asjc_cat (@asjc_list) {
                    next if(!exists($short_scats{$asjc_cat})); # Remove '(None)'
                    $wos_asjc_n{$wos_list[$i]}->{$asjc_cat}++;
                }
            }
        }
    }

    # Count __sources (journals, booktitles)
    $src_n{$db[$i]->{'__source'}}++;
    foreach my $stg_ix (@stage_ck) {
        $stat_src_n{$stages[$stg_ix]}->{$db[$i]->{'__source'}}++;
        $stat_n{$stages[$stg_ix]}++;
    }

    # Count rejections

    if(exists($db2scrres{$i})) {
        my $result = $scrres[$db2scrres{$i}];
        my ($q1, $q2, $q3) = ($result->[$S_Q1], $result->[$S_Q2], $result->[$S_Q3]);
        if($q1 < 3) {
            $src_sr_n{'S1'}->{$db[$i]->{'__source'}}++;
        }
        elsif($q2 < 3) {
            $src_sr_n{'S2'}->{$db[$i]->{'__source'}}++;
        }
        elsif($q3 < 3) {
            $src_sr_n{'S3'}->{$db[$i]->{'__source'}}++;
        }
        elsif(exists($db2assign{$i})) {
            my $assignments = $assign[$db2assign{$i}];

            my $j1 = $assignments->[$A_RV1];
            my $j2 = $assignments->[$A_RV2];

            my ($r4, $r1, $r2, $r3) = &is_eligible($review[$j1], $review[$j2]);

            if($r1 ne 'Yes') {
                $src_sr_n{'R1'}->{$db[$i]->{'__source'}}++;
            }
            elsif($r2 ne 'Yes') {
                $src_sr_n{'R2'}->{$db[$i]->{'__source'}}++;
            }
            elsif($r3 ne 'Yes') {
                $src_sr_n{'R3'}->{$db[$i]->{'__source'}}++;
            }
            elsif(!$r4) {
                $src_sr_n{'R4'}->{$db[$i]->{'__source'}}++;
            }
            elsif(!exists($db2merged{$i})) {
                warn "\$db[$i] is assigned, is not rejected, but has no merged review\n";
            }
        }
        else {
            warn "\$db[$i] has screening results, is not rejected, but is not assigned\n";
        }
    }

    # Count topic usage and assemble Sankey plot data for ASJC, topic and WoS
    # categories for papers that were screened
    if(exists($db2screen{$i})) {
        $n_corpora{'papers for screening'}++;
        $n_corpora_topic{'papers for screening'}++ if($n_topic == 0);
        $n_corpora_topic_intent{'papers for screening'}++ if($n_topic_intent == 0);
        if(!exists($db2corpus{$i})) {
            &logbook("Paper $i has been associated with a screening BibTeX entry, ",
                "but not with the corpus");
        }
        &sankey_data(\%topic_links, "DL", "SCR", @topic_list);
        &sankey_data(\%topic_intent_links, "DL", "SCR", @topic_intent_list);
        &sankey_data(\%asjc_links, "DL", "SCR", @asjc_list);
        $paper_links{'DL'}->{'SCR'}++;
        foreach my $asjc_cat (@asjc_list) {
            $asjc_stage{$stages[$ST_SCREEN]}->{$asjc_cat}++;
        }
        foreach my $wos_cat (@wos_list) {
            $wos_stage{$stages[$ST_SCREEN]}->{$wos_cat}++;
        }

        # If the papers were then assigned for review, amass further Sankey
        # plot data
        if(exists($db2assign{$i})) {
            &sankey_data(\%topic_links, "SCR", "REV", @topic_list);
            &sankey_data(\%topic_intent_links, "SCR", "REV", @topic_intent_list);
            &sankey_data(\%asjc_links, "SCR", "REV", @asjc_list);
            $paper_links{'SCR'}->{'REV'}++;
            foreach my $asjc_cat (@asjc_list) {
                $asjc_stage{$stages[$ST_REVIEW]}->{$asjc_cat}++;
            }
            foreach my $wos_cat (@wos_list) {
                $wos_stage{$stages[$ST_REVIEW]}->{$wos_cat}++;
            }

            # And if they were in the accepted final bunch of papers, then
            # record that too
            if(exists($db2merged{$i})) {
                &sankey_data(\%topic_links, "REV", "IN", @topic_list);
                &sankey_data(\%topic_intent_links, "REV", "IN", @topic_intent_list);
                &sankey_data(\%asjc_links, "REV", "IN", @asjc_list);
                $paper_links{'REV'}->{'IN'}++;
                foreach my $asjc_cat (@asjc_list) {
                    $asjc_stage{$stages[$ST_RESULT]}->{$asjc_cat}++;
                }
                foreach my $wos_cat (@wos_list) {
                    $wos_stage{$stages[$ST_RESULT]}->{$wos_cat}++;
                }
            }
            # They weren't in the accepted final bunch of papers, so
            # build a Sankey link to 'OUT'
            else {
                &sankey_data(\%topic_links, "REV", "OUT", @topic_list);
                &sankey_data(\%topic_intent_links, "REV", "OUT", @topic_intent_list);
                &sankey_data(\%asjc_links, "REV", "OUT", @asjc_list);
                $paper_links{'REV'}->{'OUT'}++;
            }
        }
        # They weren't assigned for review, so build a Sankey link to 'OUT'
        else {
            &sankey_data(\%topic_links, "SCR", "OUT", @topic_list);
            &sankey_data(\%topic_intent_links, "SCR", "OUT", @topic_intent_list);
            &sankey_data(\%asjc_links, "SCR", "OUT", @asjc_list);
            $paper_links{'SCR'}->{'OUT'}++;
        }
    }
    # They weren't screened, so build a Sankey link to 'OUT'
    else {
        &sankey_data(\%topic_links, "DL", "OUT", @topic_list);
        &sankey_data(\%topic_intent_links, "DL", "OUT", @topic_intent_list);
        &sankey_data(\%asjc_links, "DL", "OUT", @asjc_list);
        $paper_links{'DL'}->{'OUT'}++;
    }

    # Assemble counts of topic usage at different stages to report at the end
    # of the loop
    if(exists($db2scrres{$i})) {
        $n_corpora{'screening results papers'}++;
        $n_corpora_topic{'screening results papers'}++ if($n_topic == 0);
        $n_corpora_topic_intent{'screening results papers'}++ if($n_topic_intent == 0);
        if(!exists($db2screen{$i})) {
            &logbook("Paper $i has been associated with a screening results BibTeX entry, ",
                "but not with the papers for screening");
        }
    }
    if(exists($db2assign{$i})) {
        $n_corpora{'review assignments'}++;
        $n_corpora_topic{'review assignments'}++ if($n_topic == 0);
        $n_corpora_topic_intent{'review assignments'}++ if($n_topic_intent == 0);
        if(!exists($db2scrres{$i})) {
            &logbook("Paper $i has been associated with a review assignment BibTeX entry, ",
                "but not with the screening results papers");
        }
    }
    if(exists($db2merged{$i})) {
        $n_corpora{'merged reviews'}++;
        $n_corpora_topic{'merged reviews'}++ if($n_topic == 0);
        $n_corpora_topic_intent{'merged reviews'}++ if($n_topic_intent == 0);
        if(!exists($db2assign{$i})) {
            &logbook("Paper $i has been associated with a merged review BibTeX entry, ",
                "but not with any review assigment paper");
        }
    }
}

##############################################################################
# Big loop finished: report topic usage and do the Sankey plots
##############################################################################
foreach my $corpora ('original merged papers', 'papers for screening',
    'screening results papers', 'review assignments', 'merged reviews')
{
    &logbook("Of ", $n_corpora{$corpora}, " $corpora, ", $n_corpora_topic{$corpora},
        " had no topic, and ", $n_corpora_topic_intent{$corpora}, " had no",
        " topic as the search was originally intended");
}

if($parameters{'R-do-sankey'}) {
    print $R_FP <<SANKEY;
################################################################################
#
#  ####  ###  #   # #   # ##### #   #       ####  #      ###  #####  ####
# #     #   # ##  # #  #  #      # #        #   # #     #   #   #   #
#  ###  ##### # # # ###   ####    #         ####  #     #   #   #    ###
#     # #   # #  ## #  #  #       #         #     #     #   #   #       #
# ####  #   # #   # #   # #####   #         #     #####  ###    #   ####
#
################################################################################
SANKEY
    &sankey_plot($R_FP, "sankey.topics", \%topic_links);
    &sankey_plot($R_FP, "sankey.topics.intent", \%topic_intent_links);
    &sankey_plot($R_FP, "sankey.cats", \%asjc_links);
    &sankey_plot($R_FP, "sankey.papers", \%paper_links);

    warn "PROGRESS [", &iso_date(), "]: Prepared sankey plots\n";
}


#  2. Summarize Scopus and Web of Science category match
#

my (@screened_wos, @screened_asjc, @unscreened_wos, @unscreened_asjc);
my %is_screened_wos;

foreach my $wos (keys(%{$stat_wos_n{$stages[$ST_DOWNLOAD]}})) {
    if(exists($stat_wos_n{$stages[$ST_SCREEN]}->{$wos})) {
        if(&WoS::is_category($wos) && &WoS::is_removed($wos)) {
            warn "Category $wos is screened but removed\n";
            &logbook("Category $wos is screened but removed -- shifting to unscreened");
            push(@unscreened_wos, $wos);
        }
        else {
            push(@screened_wos, $wos);
            $is_screened_wos{$wos} = 1;
        }
    }
    else {
        push(@unscreened_wos, $wos);
        if(&WoS::is_category($wos) && &WoS::is_definite($wos)) {
            warn "Category $wos is unscreened but definite\n";
            &logbook("Category $wos is unscreened but definite -- may need investigation");
        }
    }
}
foreach my $asjc (keys(%{$stat_asjc_n{$stages[$ST_DOWNLOAD]}})) {
    if(exists($stat_asjc_n{$stages[$ST_SCREEN]}->{$asjc})) {
        push(@screened_asjc, $asjc);
    }
    else {
        push(@unscreened_asjc, $asjc);
    }
}
@screened_wos = sort {$a cmp $b} @screened_wos;
@unscreened_wos = sort {$a cmp $b} @unscreened_wos;
@screened_asjc = sort {$a cmp $b} @screened_asjc;
@unscreened_asjc = sort {$a cmp $b} @unscreened_asjc;

&logbook("Screened Web of Science categories (n = ", scalar(@screened_wos),
    "): \"", join("\", \"", @screened_wos), "\"");
&logbook("Screened ASJC categories (n = ", scalar(@screened_asjc),
    "): \"", join("\", \"", @screened_asjc), "\"");
&logbook("Unscreened Web of Science categories (n = ", scalar(@unscreened_wos),
    "): \"", join("\", \"", @unscreened_wos), "\"");
&logbook("Unscreened ASJC categories (n = ", scalar(@unscreened_asjc),
    "): \"", join("\", \"", @unscreened_asjc), "\"");

# Build %src_any_wos
for(my $ix = 0; $ix <= $#db; $ix++) {
    my $wos_found = 0;
    foreach my $wos_cat (keys(%{$db[$ix]->{'__wos_cat'}})) {
        if(exists($is_screened_wos{$wos_cat}) && !$wos_found) {
            $src_any_wos{$db[$ix]->{'__source'}}++;
            $wos_found++;
        }
    }
}

# This is done as a few tables:
# 1. (ASJC, n, intersect ASJC, n)

print $R_FP <<CAT_MATCH;
################################################################################
#
#  ####  ###  #####       #   #  ###  #####  #### #   #
# #     #   #   #         ## ## #   #   #   #     #   #
# #     #####   #         # # # #####   #   #     #####
# #     #   #   #         #   # #   #   #   #     #   #
#  #### #   #   #         #   # #   #   #    #### #   #
#
################################################################################

################################################################################
# ASJC / ASJC summary (and comp/soc sci)
################################################################################

CAT_MATCH

my @asjc_tab;
my @asjc_summary_tab;
foreach my $asjc_cat (sort {$a cmp $b} keys(%asjc_n)) {
    next if($asjc_cat eq '(None)');
    my $short = $short_scats{$asjc_cat};

    push(@asjc_tab, [$short, $asjc_n{$asjc_cat}, " ", "NA"]);
    if(exists($comp_sci_scats{$asjc_cat}) || exists($soc_sci_scats{$asjc_cat})) {
        push(@asjc_summary_tab, [$short, $asjc_n{$asjc_cat}, " ", "NA"]);
    } 

    if(exists($asjc_asjc_n{$asjc_cat})) {
        my $other_asjc = $asjc_asjc_n{$asjc_cat};
        next if($other_asjc eq '(None)');

        my $first_summary = 1;
        my @other = sort {$a cmp $b} keys(%$other_asjc);
        for(my $i = 0; $i <= $#other; $i++) {
            if($i == 0) {
                $asjc_tab[$#asjc_tab]->[2] = $short_scats{$other[0]};
                $asjc_tab[$#asjc_tab]->[3] = $other_asjc->{$other[0]};
            }
            else {
                push(@asjc_tab, [" ", "NA", $short_scats{$other[$i]}, $other_asjc->{$other[$i]}]);
            }

            if((exists($comp_sci_scats{$asjc_cat}) || exists($soc_sci_scats{$asjc_cat}))
                && (exists($comp_sci_scats{$other[$i]}) || exists($soc_sci_scats{$other[$i]})))
            {
                if($first_summary) {
                    $first_summary = 0;
                    $asjc_summary_tab[$#asjc_summary_tab]->[2] = $short_scats{$other[0]};
                    $asjc_summary_tab[$#asjc_summary_tab]->[3] = $other_asjc->{$other[0]};
                }
                else {
                    push(@asjc_summary_tab, [" ", "NA", $short_scats{$other[$i]},
                        $other_asjc->{$other[$i]}]);
                }
            }
            
        }
    }
}
print $R_FP "asjc.conf <- data.frame(\`ASJC category\` = c(\"", join("\", \"",
    map {$_->[0]} @asjc_tab), "\"),\n    \`Records\` = c(", join(", ", map {$_->[1]} @asjc_tab),
    "),\n    \`Other ASJC\` = c(\"", join("\", \"", map {$_->[2]} @asjc_tab), "\"),\n    ",
    "\`Intersecting records\` = c(", join(", ", map {$_->[3]} @asjc_tab), "), check.names = FALSE)\n";
print $R_FP "latex_table(asjc.conf, caption = \"Table of ASJC category record counts ",
    "and any intersection with other ASJC categories\", label = \"tab:asjc-conf\", dig = 6,
    file = table.asjc.conf)\n";

print $R_FP "asjc.summary <- data.frame(\`ASJC category\` = c(\"", join("\", \"",
    map {$_->[0]} @asjc_summary_tab), "\"),\n    \`Records\` = c(",
    join(", ", map {$_->[1]} @asjc_summary_tab), "),\n    \`Other ASJC\` = ",
    "c(\"", join("\", \"", map {$_->[2]} @asjc_summary_tab), "\"),\n    ",
    "\`Intersecting records\` = c(", join(", ", map {$_->[3]} @asjc_summary_tab),   
    "), check.names = FALSE)\n";
print $R_FP "latex_table(asjc.conf, caption = \"Table of ASJC category record counts in social and ",
    "computing sciences, and any intersection with other ASJC categories in those areas\", label = ",
    "\"tab:asjc-summary-conf\", dig = 2, file = table.asjc.short)\n";

print $R_FP <<COMMENT1;

################################################################################
# Web of Science and self-intersection
################################################################################

COMMENT1

my @wos_tab;
foreach my $wos_cat (sort {$a cmp $b} keys(%wos_n)) {

    push(@wos_tab, [$wos_cat, "TOTAL", "NA", $wos_n{$wos_cat}]);

    # N.B. %wos_n excludes rejected categories; %wos_wos_n does not
    if(exists($wos_wos_n{$wos_cat})) {
        my $other_wos = $wos_wos_n{$wos_cat};

        foreach my $other_cat (sort {$a cmp $b} keys(%$other_wos)) {
            my $tf = 'FALSE';

            if(exists($is_screened_wos{$wos_cat})) {
                $tf = 'TRUE';
            }

            push(@wos_tab, [$wos_cat, $other_cat, $tf, $other_wos->{$other_cat}]);
        }
    }
}
print $R_FP "wos.conf <- data.frame(\`WoS category\` = c(\"", join("\", \"",
    map {$_->[0]} @wos_tab), "\"),\n    \`Intersecting WoS category\` = ",
    "c(\"", join("\", \"", map {$_->[1]} @wos_tab), "\"),\n    \`Included?\` = ",
    "c(", join(", ", map {$_->[2]} @wos_tab), "),\n    \`Number of records\` = ",
    "c(", join(", ", map {$_->[3]} @wos_tab), "), check.names = FALSE)\n";
print $R_FP "latex_table(wos.conf, caption = \"Table of Web of Science category record",
    "counts and any intersection with other Web of Science categories\", label = ",
    "\"tab:wos-conf\", dig = 2, file = table.wos.conf)\n";

print $R_FP <<COMMENT2;

################################################################################
# Web of Science and ASJC
################################################################################

COMMENT2

my @wos_asjc_tab;
my @wos_asjc_summary_tab;
my @sort_asjc_soc;
my @sort_asjc_comp;
foreach my $asjc_cat (keys(%short_scats)) {
    push(@sort_asjc_soc, $asjc_cat) if(exists($soc_sci_scats{$asjc_cat}));
    push(@sort_asjc_comp, $asjc_cat) if(exists($comp_sci_scats{$asjc_cat}));
}
@sort_asjc_soc = sort {$a cmp $b} @sort_asjc_soc;
@sort_asjc_comp = sort {$a cmp $b} @sort_asjc_comp;
my %doi_wos_ratio;

foreach my $wos_cat (keys(%wos_asjc_n)) {
    my @row;
    my @summary_row;
    push(@row, $wos_cat);
    push(@summary_row, $wos_cat);

    my $n_comp = 0;
    foreach my $asjc_comp (@sort_asjc_comp) {
        if(exists($wos_asjc_n{$wos_cat}->{$asjc_comp})) {
            push(@row, $wos_asjc_n{$wos_cat}->{$asjc_comp});
            $n_comp += $row[$#row];
        }
        else {
            push(@row, 0);
        }
    }
    push(@summary_row, $n_comp);
    push(@row, $n_comp);

    my $n_soc = 0;
    foreach my $asjc_soc (@sort_asjc_soc) {
        if(exists($wos_asjc_n{$wos_cat}->{$asjc_soc})) {
            push(@row, $wos_asjc_n{$wos_cat}->{$asjc_soc});
            $n_soc += $row[$#row];
        }
        else {
            push(@row, 0);
        }
    }
    push(@summary_row, $n_soc);
    push(@row, $n_soc);

    if($n_soc > 0) {
        push(@summary_row, $n_comp / $n_soc);
        push(@wos_asjc_summary_tab, \@summary_row);
        push(@row, $n_comp / $n_soc);
    }
    else {
        # Summary table ignores cases where $n_soc == 0
        push(@row, "NA");
    }

    push(@wos_asjc_tab, \@row);
    $doi_wos_ratio{$wos_cat} = [$n_soc, $n_comp];
}

@wos_asjc_tab = sort {
    # This absolute gobbledegook is supposed to put the smallest ratios at 
    # the front of the list, and NA (where n. soc == 0) at the end, sorting
    # alphabetically by category name
    ($b->[$#{$b}] eq "NA") ? (
        ($a->[$#{$a}] eq "NA") ? ($a->[0] cmp $b->[0]) : -1
    ) : (
        ($a->[$#{$a}] eq "NA") ? 1 : (
            ($b->[$#{$b}] == $a->[$#{$a}]) ? ($a->[0] cmp $b->[0]) : ($a->[$#{$a}] <=> $b->[$#{$b}])
        )
    )
} @wos_asjc_tab;

@wos_asjc_summary_tab = sort {
    # There are no 'NA's in the summary table
    ($b->[$#{$b}] == $a->[$#{$a}]) ? ($a->[0] cmp $b->[0]) : ($a->[$#{$a}] <=> $b->[$#{$b}])
} @wos_asjc_summary_tab;

print $R_FP "wos.asjc.summary <- data.frame(\`Web of Science Category\` = c(\"",
    join("\", \"", map {$_->[0]} @wos_asjc_summary_tab), "\"),\n    ",
    "\`ASJC Comp. Sci.\` = c(",
    join(", ", map {$_->[1]} @wos_asjc_summary_tab), "),\n    ",
    "\`ASJC Soc. Sci.\` = c(",
    join(", ", map {$_->[2]} @wos_asjc_summary_tab), "),\n    ",
    "\`Ratio\` = c(",
    join(", ", map {$_->[3]} @wos_asjc_summary_tab), "), check.names = FALSE)\n";
print $R_FP "latex_table(wos.asjc.summary, caption = \"Table of Web of Science category ",
    "matches against Scopus ASJC categories in Computational and Social Sciences for papers ",
    "with reliably matched DOIs\", label = ",
    "\"tab:wos-asjc\", dig = 4, file = table.asjc.wos.short)\n";

print $R_FP "wos.asjc <- data.frame(\`Web of Science Category\` = c(\"",
    join("\", \"", map {$_->[0]} @wos_asjc_tab), "\"),\n    ";
for(my $i = 0; $i <= $#sort_asjc_comp; $i++) {
    print $R_FP "\`", $short_scats{$sort_asjc_comp[$i]}, "\` = c(",
        join(", ", map {$_->[$i + 1]} @wos_asjc_tab), "),\n    ";
}
print $R_FP "\`Total ASJC Comp. Sci.\` = c(",
    join(", ", map {$_->[$#sort_asjc_comp + 2]} @wos_asjc_tab), "),\n    ";
for(my $i = 0; $i <= $#sort_asjc_soc; $i++) {
    print $R_FP "\`", $short_scats{$sort_asjc_soc[$i]}, "\` = c(",
        join(", ", map {$_->[$#sort_asjc_comp + 3 + $i]} @wos_asjc_tab), "),\n    ";
}
print $R_FP "\`Total ASJC Soc. Sci.\` = c(",
    join(", ", map {$_->[$#sort_asjc_comp + 4 + $#sort_asjc_soc]} @wos_asjc_tab), "),\n    ",
    "\`Comp. / Soc.\` = c(",
    join(", ", map {$_->[$#sort_asjc_comp + 5 + $#sort_asjc_soc]} @wos_asjc_tab), "), ",
    "check.names = FALSE)\n";

print $R_FP "latex_table(wos.asjc, caption = \"Table of Web of Science category ",
    "matches against Computational and Social Sciences Scopus ASJC categories, ",
    "for papers with reliably matched DOIs\", label = \"tab:wos-asjc-full\", ",
    "dig = 2, file = table.asjc.wos)\n";

print $R_FP <<COMMENT4;

################################################################################
# All categories included
################################################################################

COMMENT4

my @n_inc_cats = map { exists($wos_n{$_}) ? $wos_n{$_} : 0 } @screened_wos;
my @n_inc_scrn = map { exists($stat_wos_n{$stages[$ST_SCREEN]}->{$_}) 
    ? $stat_wos_n{$stages[$ST_SCREEN]}->{$_} : 0 } @screened_wos;
my @n_inc_revw = map { exists($stat_wos_n{$stages[$ST_REVIEW]}->{$_})
    ? $stat_wos_n{$stages[$ST_REVIEW]}->{$_} : 0 } @screened_wos;
my @n_inc_rslt = map { exists($stat_wos_n{$stages[$ST_RESULT]}->{$_})
    ? $stat_wos_n{$stages[$ST_RESULT]}->{$_} : 0 } @screened_wos;

print $R_FP "inc.cats <- as.data.frame(matrix(NA, nrow = ", scalar(@screened_wos), ", ncol = 6))\n";
print $R_FP "names(inc.cats) = c(\"Category\", \"N.\", \"S.\", \"R.\", \"I.\", \"P.\")\n";
print $R_FP "inc.cats\$Category = c(\"", join("\", \"", @screened_wos), "\")\n";
print $R_FP "inc.cats\$\`N.\` = c(", join(", ", @n_inc_cats), ")\n";
print $R_FP "inc.cats\$\`S.\` = c(", join(", ", @n_inc_scrn), ")\n";
print $R_FP "inc.cats\$\`R.\` = c(", join(", ", @n_inc_revw), ")\n";
print $R_FP "inc.cats\$\`I.\` = c(", join(", ", @n_inc_rslt), ")\n";
print $R_FP "inc.cats\$\`P.\` = inc.cats\$\`I.\` / inc.cats\$`S.`\n";
print $R_FP "latex_table(subset(inc.cats, R. >= 1), ",
    "caption = \"Web of Science categories associated with at least one paper reviewed, ",
    "with number of records allocated to that category (N.), number ",
    "screened (S.), number reviewed (R.), and number included (I.). ",
    "Column P. shows the proportion of screened papers that are included (\$I / S\$)\", ",
    "label = \"tab:inc-cats\", file = table.inc.wos, dig = 2, pct = c(\"P.\"))\n";

# N.B. Lots of code (~ 100 lines) now deleted -- see slr-results-old-2026-02-23.pl
# if you want to check it out. Global variables gone: %wos_comp, %wos_soc (now
# use %doi_wos_ratio {WoS cat}->[n. soc, n. comp]), and @asjc_vars. Files gone
# are $stage_pdf_var{everything} and data.cats. Deleting those gets rid of
# %stage_title, @stage_titles, and @stage_pdf_vars. %wos_comp and %wos_soc were
# used in the code below for Step 3.

#  3. Identify journals that cover agreed categories. The original work used
#     algorithm 2 of GAjournal.pl, selecting the top 5 journals.

################################################################################
#
#  ####  ###  #   # ####   #### #####  ####
# #     #   # #   # #   # #     #     #
#  ###  #   # #   # ####  #     ####   ###
#     # #   # #   # #   # #     #         #
# ####   ###   ###  #   #  #### ##### ####
#
################################################################################

my $src_table_file = join("/", $parameters{'output-dir'}, $parameters{'tex-dir'},
    $output_files{'table-sources'});
open(CAT_TABLE, ">:encoding(UTF-8)", $src_table_file) or die "Cannot create ",
    "long table \"$src_table_file\": $!\n";

print CAT_TABLE <<LONG_START;
% Add \\usepackage{longtable} to the document preamble
% Add \\usepackage{multirow} to the document preamble
% Add \\usepackage[table]{xcolor} to the document preamble

\\begin{longtable}[c]{rp{7cm}cr}
    \\endfirsthead
    \\toprule
    Rank & Source & Used? & Records \\\\
    \\midrule
    \\endhead
    \\endfoot
    \\bottomrule
    \\caption{Top publication sources for each category, and the source used.}
    \\label{tab:wos-any-src}
    \\endlastfoot

LONG_START

my %inc_cat_n;      # {WoS definite cat} -> count of papers with that category
foreach my $cat (@screened_wos) {
    print CAT_TABLE "    \\rowcolor{JASSScolor} \\multicolumn{4}{l}{",
        "\\textbf{\\textcolor{white}{$cat}}} \\\\\n";

    my %srcs;       # Sources for this category to number of papers
    my %src_other;  # Sources to other categories this source picks up

    $inc_cat_n{$cat} = 0;
    foreach my $src (keys(%src_wos)) {
        if(exists($src_wos{$src}->{$cat})) {
            $inc_cat_n{$cat} += $src_wos{$src}->{$cat};
            $srcs{$src} += $src_wos{$src}->{$cat};
        }
        foreach my $other_cat (keys(%{$src_wos{$src}})) {
            if($other_cat ne $cat) {
                $src_other{$src}->{$other_cat} += $src_wos{$src}->{$other_cat};
            }
        }
    }

    my @top_src = sort { $srcs{$b} <=> $srcs{$a} } keys(%srcs);

    my $done_an_included_src = 0;
    TOP_N: for(my $i = 0; $i <= $#top_src; $i++) {
        my $src = $top_src[$i];
        if($i < $parameters{'top-any-cat'}) {
            if(exists($shortj{$src})) {
                my $print_src = $shortj{$src};
                $print_src =~ s/&/\\&/g;
                print CAT_TABLE "    \\nopagebreak ", ($i + 1), " & ", $print_src,
                    " & \$\\bullet\$ & ", $srcs{$src}, " \\\\\n";
                $done_an_included_src = 1;
            }
            elsif(exists($abbrevj{$src})) {
                my $print_src = $abbrevj{$src};
                $print_src =~ s/&/\\&/g;
                print CAT_TABLE "    \\nopagebreak ", ($i + 1), " & ", $print_src,
                    " & \$\\circ\$ & ", $srcs{$src}, " \\\\\n";
            }
            else {
                my $print_src = $src;
                $print_src =~ s/&/\\&/g;
                print CAT_TABLE "    \\nopagebreak ", ($i + 1), " & $print_src & \$\\circ\$ & ",
                    $srcs{$src}, " \\\\\n";
                warn "Add \"$print_src\" to \%abbrevj\n";
                &logbook("Add \"$print_src\" to \%abbrevj");
            }
        }
        elsif($done_an_included_src) {
            last TOP_N;
        }
        elsif(exists($shortj{$src})) {
            my $print_src = $shortj{$src};
            $print_src =~ s/&/\\&/g;
            print CAT_TABLE "    \\nopagebreak ", ($i + 1), " & ", $print_src,
                " & \$\\bullet\$ & ", $srcs{$src}, " \\\\\n";
            $done_an_included_src = 1;
        }
    }
}
print CAT_TABLE <<LONG_END;
\\end{longtable}
LONG_END
close(CAT_TABLE);

my @top_inc_src = sort { $src_any_wos{$b} <=> $src_any_wos{$a} } keys(%src_any_wos);

my @show_stages = ($ST_SCREEN, $ST_REVIEW, $ST_RESULT);
my $show_titles = join(" & ", map { substr($stage_titles[$_], 0, 1)."." } @show_stages);
my $show_cols = "r" x scalar(@show_stages);

my $all_src_table_file = join("/", $parameters{'output-dir'}, $parameters{'tex-dir'},
    $output_files{'table-src-inc'});
open(CAT_TABLE_ALL, ">:encoding(UTF-8)", $all_src_table_file)
    or die "Cannot create all category source counts table in \"$all_src_table_file\": $!\n";
print CAT_TABLE_ALL "\\begin{table}[ht!]\n\\centering\n    \\begin{tabular}{rp{5cm}r${show_cols}rrr}\n";

print CAT_TABLE_ALL "        \\toprule\n        Rank & Source & Records & $show_titles & !ABM & !Soc & !Emp \\\\\n";
print CAT_TABLE_ALL "        \\midrule\n";

my $n_top_inc_src_used = 0;
my $sum_top_inc_used = 0;
my @sum_stages = map { 0 } @stages;
my $sum_abm = 0;
my $sum_soc = 0;
my $sum_emp = 0;
my %ck_all_sources;
for(my $i = 0; $i <= $#top_inc_src; $i++) {
    my $src = $top_inc_src[$i];
    foreach my $stage (@show_stages) {
        if(exists($stat_src_n{$stages[$stage]}->{$src})) {
            $sum_stages[$stage] += $stat_src_n{$stages[$stage]}->{$src};
        }
        else {
            $stat_src_n{$stages[$stage]}->{$src} = 0;
        }
    }
    if($i == $parameters{'top-all-cat'}) {
        print CAT_TABLE_ALL "        \\midrule\n";
    }
    my $n_abm = 0;
    my $n_soc = 0;
    my $n_emp = 0;
    if(exists($shortj{$src})) {
        if(exists($src_sr_n{'S1'}->{$src})) {
            $n_abm += $src_sr_n{'S1'}->{$src};
        }
        if(exists($src_sr_n{'R1'}->{$src})) {
            $n_abm += $src_sr_n{'R1'}->{$src};
        }
        if(exists($src_sr_n{'S2'}->{$src})) {
            $n_soc += $src_sr_n{'S2'}->{$src};
        }
        if(exists($src_sr_n{'R2'}->{$src})) {
            $n_soc += $src_sr_n{'R2'}->{$src};
        }
        if(exists($src_sr_n{'S3'}->{$src})) {
            $n_emp += $src_sr_n{'S3'}->{$src};
        }
        if(exists($src_sr_n{'R3'}->{$src})) {
            $n_emp += $src_sr_n{'R3'}->{$src};
        }
        $sum_abm += $n_abm;
        $sum_soc += $n_soc;
        $sum_emp += $n_emp;
    }
    if($i < $parameters{'top-all-cat'}) {
        if(exists($shortj{$src})) {
            my $print_src = "\\textbf{".$shortj{$src}."}";
            $print_src =~ s/&/\\&/g;
            print CAT_TABLE_ALL "        ", join(" & ", $i + 1, $print_src, $src_any_wos{$src}, 
                map { $stat_src_n{$stages[$_]}->{$src} } @show_stages),
                " & $n_abm & $n_soc & $n_emp \\\\\n";
            $n_top_inc_src_used++;
            $sum_top_inc_used += $src_any_wos{$src};
            $ck_all_sources{$src}++;
        }
        elsif(exists($abbrevj{$src})) {
            my $print_src = $abbrevj{$src};
            $print_src =~ s/&/\\&/g;
            print CAT_TABLE_ALL "        ", join(" & ", $i + 1, $print_src, $src_any_wos{$src},
                map { $stat_src_n{$stages[$_]}->{$src} } @show_stages), " & -- & -- & -- \\\\\n";
        }
        else {
            my $print_src = $src;
            $print_src =~ s/&/\\&/g;
            print CAT_TABLE_ALL "        ", join(" & ", $i + 1, $print_src, $src_any_wos{$src},
                map { $stat_src_n{$stages[$_]}->{$src} } @show_stages), " & -- & -- & -- \\\\\n";
            warn "Add \"$src\" to \%abbrevj\n";
            &logbook("Add \"$src\" to \%abbrevj");
        }
    }
    elsif($n_top_inc_src_used == scalar(keys(%shortj))) {
        last;
    }
    elsif(exists($shortj{$src})) {
        my $print_src = "\\textbf{".$shortj{$src}."}";
        $print_src =~ s/&/\\&/g;
        print CAT_TABLE_ALL "        ", join(" & ", $i + 1, $print_src, $src_any_wos{$src},
            map { $stat_src_n{$stages[$_]}->{$src} } @show_stages),
            " & $n_abm & $n_soc & $n_emp \\\\\n";
        $n_top_inc_src_used++;
        $sum_top_inc_used += $src_any_wos{$src};
        $ck_all_sources{$src}++;
    }
}
my @extra_src;
foreach my $src (keys(%shortj)) {
    if(!exists($ck_all_sources{$src})) {
        push(@extra_src, $src);
    }
}
if(scalar(@extra_src) > 0) {
    @extra_src = sort { $shortj{$_} cmp $shortj{$_} } @extra_src;
    print CAT_TABLE_ALL "    \\midrule\n";
    foreach my $src (@extra_src) {
        foreach my $stage (@show_stages) {
            if(exists($stat_src_n{$stages[$stage]}->{$src})) {
                $sum_stages[$stage] += $stat_src_n{$stages[$stage]}->{$src};
            }
            else {
                $stat_src_n{$stages[$stage]}->{$src} = 0;
            }
        }
        my $n_abm = 0;
        my $n_soc = 0;
        my $n_emp = 0;
        if(exists($src_sr_n{'S1'}->{$src})) {
            $n_abm += $src_sr_n{'S1'}->{$src};
        }
        if(exists($src_sr_n{'R1'}->{$src})) {
            $n_abm += $src_sr_n{'R1'}->{$src};
        }
        if(exists($src_sr_n{'S2'}->{$src})) {
            $n_soc += $src_sr_n{'S2'}->{$src};
        }
        if(exists($src_sr_n{'R2'}->{$src})) {
            $n_soc += $src_sr_n{'R2'}->{$src};
        }
        if(exists($src_sr_n{'S3'}->{$src})) {
            $n_emp += $src_sr_n{'S3'}->{$src};
        }
        if(exists($src_sr_n{'R3'}->{$src})) {
            $n_emp += $src_sr_n{'R3'}->{$src};
        }
        $sum_abm += $n_abm;
        $sum_soc += $n_soc;
        $sum_emp += $n_emp;
        my $print_src = "\\textbf{".$shortj{$src}."}";
        $print_src =~ s/&/\\&/g;
        print CAT_TABLE_ALL "        -- & ", join(" & ", $print_src, 0,
            map { $stat_src_n{$stages[$_]}->{$src} } @show_stages), 
            " & $n_abm & $n_soc & $n_emp \\\\\n";
    }
}

print CAT_TABLE_ALL "        \\midrule\n";
print CAT_TABLE_ALL "        \\multicolumn{2}{l}{\\textbf{Totals for ",
    "publication sources with screen > 0}} & $sum_top_inc_used & ",
    join(" & ", map { $sum_stages[$_] } @show_stages),
    " & $sum_abm & $sum_soc & $sum_emp \\\\\n";
print CAT_TABLE_ALL "        \\bottomrule\n";
print CAT_TABLE_ALL "    \\end{tabular}\n\\";
print CAT_TABLE_ALL "    \\caption{Table of ranked publication sources covering all ",
    "Web of Science categories, together with the numbers of articles screened (S.), ",
    "reviewed (R.), and included (I.), and reasons for rejection at either screen ",
    "or review stage, for not being an agent-based model (!ABM), not being in the ",
    "social sciences (!Soc), or not being empirical (!Emp)}\n";
print CAT_TABLE_ALL "    \\label{tab:wos-all-src}\n\\end{table}";
close(CAT_TABLE_ALL);

# More lots of code deleted. More lots of global variables gone:
# @extra_cats, %extra_src_n, %inc_corp_n, %extra_corp_n, %inc_src_cat_n,
# %extra_src_cat_n, %inc_corp_cat_n, %extra_corp_cat_n, @src_list,
# @corp_src_list, @top_extra_src, @top_inc_corp, @top_extra_corp,
# %inc_prog, %inc_extra_prog, %corp_inc_prog, %corp_inc_extra_prog,
# @journal_list, @extra_journal_list, @corp_journal_list, @extra_corp_journal_list,
# @inc_journals, @inc_extra_journals, @corp_inc_jouranls, @corp_inc_extra_journals,
# %any_journals, @any_journ, @disp_journ

# More graphs and outputs gone:
# bar-dl-src, bar-corp-src, bar-dl-cat-src, bar-corp-cat-src, bar-dl-all-src,
# bar-corp-all-src, bar-cat-src
#
# table-sources (reused), table-corp-sources, table-src-inc (reused), table-corp-inc, 
# table-src-extra, table-corp-extra, table-journals, data-journals
#
# Parameters gone:
# top-n-table, top-n-include, R-min-cat-journal


#  4. Summarize topics and category counts in papers selected for screening
#
#  5. Summarize topics, category counts and journals in papers post-screening
#     -- including 'uncertainty' for disagreements
#
#  6. Summarize topics, category counts and journals in papers post-review
#     -- including 'uncertainty' for disagreements
#
# The code below covers all three of the above. It is kept in, but arguably
# could be removed for the sake of efficiency as none of these diagrams are
# to be used in the SLR

print $R_FP <<SUMMARY;
################################################################################
#
#  #### #####  ###   #### #####        ####  ###  #   # #   # #####  ####
# #       #   #   # #     #           #     #   # #   # ##  #   #   #
#  ###    #   ##### #  ## ####        #     #   # #   # # # #   #    ###
#     #   #   #   # #   # #           #     #   # #   # #  ##   #       #
# ####    #   #   #  #### #####        ####  ###   ###  #   #   #   ####
#
################################################################################
SUMMARY

my %summary;
foreach my $key ('__wos_cat', '__asjc_cat', '__topics', '__topics_intent', '__source') {
    $summary{$key} = {};

    foreach my $heading ($stages[$ST_REVIEW], $stages[$ST_RESULT]) {
        $summary{$key}->{$heading} = {};
        $summary{$key}->{$heading.'.err'} = {};

        if($key =~ /^__asjc_cat/) {
            foreach my $scat (keys(%short_scats)) {
                $summary{$key}->{$heading}->{$scat} = 0;
                $summary{$key}->{$heading.'.err'}->{$scat} = 0;
            }
        }
    }
}

my %in_out_disputed;
for(my $i = 0; $i <= $#screen; $i++) {
    my $j = $screen2db{$i};
    my $k = $db2scrres{$j};
    my $n_in = $scrres[$k]->[$S_Q3];

    foreach my $key (keys(%summary)) {
        my @values;

        if($key eq '__source') {
            # It is at this point that I began to regret adding '__source'
            # to the list of keys with which to initialize %summary above...
            push(@values, $db[$j]->{$key});
        }
        else {
            @values = keys(%{$db[$j]->{$key}});
        }
        foreach my $topic_cat_journ (@values) {
            if($key eq '__source' && exists($shortj{$topic_cat_journ})) {
                # ...And by now I'm really regretting it
                $topic_cat_journ = $shortj{$topic_cat_journ};
            }
            elsif($key eq '__source' && exists($abbrevj{$topic_cat_journ})) {
                $topic_cat_journ = $abbrevj{$topic_cat_journ};
            }

            if(exists($db2assign{$j})) {
                $in_out_disputed{$i} = $stages[$ST_REVIEW];
                my $l = $db2assign{$j};
                my @q = &aq123($assign[$l], \@review);
                my $disputed = 0;
                foreach my $a (@q) {
                    $disputed = 1 if($a eq "Disputed");
                }
                $summary{$key}->{$stages[$ST_REVIEW]}->{$topic_cat_journ}++;

                if(exists($db2merged{$j})) {
                    $summary{$key}->{$stages[$ST_RESULT]}->{$topic_cat_journ}++;
                }
                elsif($disputed) {
                    $summary{$key}->{$stages[$ST_RESULT].'.err'}->{$topic_cat_journ}++
                }
            }
            elsif($n_in > 0) {
                $summary{$key}->{$stages[$ST_REVIEW].'.err'}->{$topic_cat_journ}++;
                $in_out_disputed{$i} = 'dispute';
            }
            else {
                $in_out_disputed{$i} = 'reject';
            }
        }
    }
}

foreach my $plot (
    ['__source', 'bar.journal.stage', 'Journals'],
    ['__wos_cat', 'bar.cat.stage', 'Web of Science Categories'],
    ['__asjc_cat', 'bar.asjc.stage', 'ASJC Categories', \&sort_asjc],
    ['__topics', 'bar.topic.stage', 'Topics (as Searched)', \&sort_topics],
    ['__topics_intent', 'bar.intent.stage', 'Topics', \&sort_topics]
) {
    my ($key, $var, $title, $sort) = @$plot;
    my @headers = sort { $a cmp $b } keys(%{$summary{$key}});
    my $table_label = $var;
    $table_label =~ s/\./-/g;
    $table_label =~ s/^bar-/tab:/;

    my @outer_bar = sort {
        defined($sort) ? &$sort($a, $b) : ($b cmp $a)
    } (keys(%{$summary{$key}->{$stages[$ST_REVIEW]}}));
    
    my $nrow = scalar(@outer_bar);
    print $R_FP "df_$key = as.data.frame(matrix(0, nrow = $nrow, ncol = ",
        scalar(@headers), "))\n";
    print $R_FP "names(df_$key) = c(\"", join("\", \"", @headers), "\")\n";
    print $R_FP "row.names(df_$key) = c(\"", join("\", \"", @outer_bar), "\")\n";

    foreach my $header (@headers) {
        print $R_FP "df_$key\$$header = c(";
        for(my $i = 0; $i <= $#outer_bar; $i++) {
            print $R_FP ", " if($i > 0);
            if(exists($summary{$key}->{$header}->{$outer_bar[$i]})) {
                print $R_FP $summary{$key}->{$header}->{$outer_bar[$i]};
            }
            else {
                if($key eq '__asjc_cat') { # Added for bug-fixing. Not called
                    warn "No summary for $header, row $outer_bar[$i] in ASJC cat plot!\n";
                }
                print $R_FP "0";
            }
        }
        print $R_FP ")\n";
    }

    print $R_FP "logbook(\"Plotting barchart of \\\"$title\\\"\")\n";
    print $R_FP "berr.pdf($var, df_$key, c(\"$stages[$ST_REVIEW]\", \"$stages[$ST_RESULT]\"), ",
        "\"$title\", proportions = bar.p, pal = c(lit.pal\$$stages[$ST_REVIEW], ",
        "lit.pal\$$stages[$ST_RESULT]))\n";
    print $R_FP "latex_table(df_$key, caption = \"$title: numbers and uncertainties ",
        "at different stages during the systematic literature review process\", ",
        "label = \"$table_label\", file = gsub(pdf.dir, tex.dir, gsub(\".pdf\$\", ",
        "\".tex\", $var)))\n";
}

warn "PROGRESS [", &iso_date(), "]: Summarized topics, category counts and ",
    "journals in screening, post-screen and merged results\n";

################################################################################
#
# ####  ####   ###   #### #   #  ###
# #   # #   #   #   #     ## ## #   #
# ####  ####    #    ###  # # # #####
# #     #   #   #       # #   # #   #
# #     #   #  ###  ####  #   # #   #
#
################################################################################

if(open(MRG, "<", $input_files{'merge-output'})) {
    my $wos = 0;
    my %scopus;
    my $record_merge;
    while(my $line = <MRG>) {
        if($line =~ /^Read (\d+) papers from file "(.+)"/) {
            my ($n, $file) = ($1, $2);
            if($file =~ /\/wos\//) {
                $wos += $n;
            }
            elsif(exists($scopus_cats{$file})) {
                $scopus{$scopus_cats{$file}} += $n;
            }
            else {
                my @path = split(/\//, $file);
                if(exists($scopus_cats{$path[$#path]})) {
                    $scopus{$scopus_cats{$path[$#path]}} += $n;
                }
                else {
                    warn "Scopus file \"$file\" not anticipated\n";
                    $scopus{$file} += $n;
                }
            }
        }
        elsif($line =~ /^Database size is (\d+)/) {
            $record_merge = $1;
        }
    }
    close(MRG);
    my $wos_categories = 0;
    foreach my $cat (keys(%inc_cat_n)) {
        $wos_categories += $inc_cat_n{$cat};
    }

    my @screening = (0, 0, 0, 0);
    foreach my $result (@scrres) {
        $screening[0]++;
        if($$result[$S_Q1] < 3) {
            $screening[1]++;
        }
        elsif($$result[$S_Q2] < 3) {
            $screening[2]++;
        }
        elsif($$result[$S_Q3] < 3) {
            $screening[3]++;
        }
    }

    my @assessed = (0, 0, 0, 0, 0);
    foreach my $assignment (@assign) {
        $assessed[0]++;
        if(exists($review[$$assignment[$A_RV1]])
            && exists($review[$$assignment[$A_RV2]])) 
        {
            my $rv1 = $review[$$assignment[$A_RV1]];
            my $rv2 = $review[$$assignment[$A_RV2]];

            my ($accepted, $is_abm, $is_soc, $is_emp) = &is_eligible($rv1, $rv2);

            if($is_abm ne 'Yes') {
                $assessed[1]++;
            }
            elsif($is_soc ne 'Yes') {
                $assessed[2]++;
            }
            elsif($is_emp ne 'Yes') {
                $assessed[3]++;
            }
            elsif(!$accepted) {
                $assessed[4]++;
            }
        }
        else {
            die "Assignment ", ($assessed[0] - 1), " [", join(", ", @$assignment),
                "] lacks valid entries in review for A_RV1 ($A_RV1) and A_RV2 ($A_RV2)\n";
        }
    }
    my $included = scalar(@merged);
    &logbook("Preparing PRISMA diagram file ", $output_files{'R-prisma-flow'});
    &print_prisma($output_files{'R-prisma-flow'}, $wos, \%scopus, $record_merge, $wos_categories,
        \@screening, \@assessed, $included);
}
else {
    warn "Cannot prepare PRISMA diagram as merge output file \"",
        $input_files{'merge-output'}, "\" could not be read: $!\n";
    &logbook("No PRISMA diagram will be prepared as merge output file \"",
        $input_files{'merge-output'}, "\" could not be read");
}
# 6a. Words in the abstract or title that are most closely associated with
#     rejection, acceptance and disputed screened papers. Display as word clouds.

if($parameters{'R-do-cloud'}) {
    print $R_FP <<CLOUD;
################################################################################
#
# #   #  ###  ####  ####         #### #      ###  #   # ####   ####
# #   # #   # #   # #   #       #     #     #   # #   # #   # #
# # # # #   # ####  #   #       #     #     #   # #   # #   #  ###
# # # # #   # #   # #   #       #     #     #   # #   # #   #     #
#  # #   ###  #   # ####         #### #####  ###   ###  ####  ####
#
################################################################################
CLOUD
    my %title_words;
    my %abstract_words;
    my %title_totals;
    my %abstract_totals;
    for(my $i = 0; $i <= $#screen; $i++) {
        my $status = $in_out_disputed{$i};
        my $j = $screen2db{$i};

        $title_totals{$status}++;
        $title_totals{'__count'}++;
        $abstract_totals{$status}++;
        $abstract_totals{'__count'}++;

        foreach my $text (['title', \%title_words], ['abstract', \%abstract_words]) {
            my ($key, $words) = @$text;

            if(exists($db[$j]->{$key})) {
                my $value = &TextTK::azns($db[$j]->{$key});

                my %in;
                foreach my $word (split(" ", $value)) {
                    $in{$word}++;
                }
                foreach my $word (keys(%in)) {
                    $words->{$word}->{$status}++;
                    $words->{$word}->{'__count'}++;
                }
            }
        }
    }

    foreach my $wordcloud (['title', \%title_words, \%title_totals],
        ['abstract', \%abstract_words, \%abstract_totals])
    {
        my ($text, $words, $totals) = @$wordcloud;

        my $n = $totals->{'__count'};

        foreach my $status ('review', 'reject', 'dispute') {
            my @df_word;
            my @df_freq;

            my $p = $totals->{$status} / $n;

            foreach my $word (keys(%$words)) {
                if(exists($words->{$word}->{$status})
                    && $words->{$word}->{$status} * $p > (1 - $p) * $words->{$word}->{'__count'} / 4)
                {
                    push(@df_word, $word);
                    push(@df_freq, $words->{$word}->{$status});
                }
            }

            if(scalar(@df_word) > 0) {
                print $R_FP "logbook(\"Drawing word cloud of \\\"$text $status\\\"\")\n";
                print $R_FP "df.$text.$status = data.frame(word = c(\"",
                    join("\", \"", @df_word), "\"),\n\tfreq = c(",
                    join(", ", @df_freq), "))\n";
                print $R_FP "wc.$text.$status = wordcloud2(df.$text.$status, ",
                    "minSize = cloud.min.fontsize, fontFamily = cloud.font.family)\n";
                print $R_FP "save_html(wc.$text.$status, cloud.$text.$status)\n";    
            }
        }
    }

    warn "PROGRESS [", &iso_date(), "]: Prepared word clouds\n";
}

################################################################################
#                                                                              #
#  #### #     ####        ####  #####  #### #   # #     #####  ####            #
# #     #     #   #       #   # #     #     #   # #       #   #                #
#  ###  #     ####        ####  ####   ###  #   # #       #    ###             #
#     # #     #   #       #   # #         # #   # #       #       #            #
# ####  ##### #   #       #   # ##### ####   ###  #####   #   ####             #
#                                                                              #
################################################################################

#  7. Distributions of time period and spatial extent (RQ1)
#     -- This and other distributions should compare HPC with PC only
#
#  8. Distributions of numbers of agents (RQ2)
#
#  9. Distributions of numbers of simulations (RQ3)
#
# It is more efficient to handle these three outputs simultaneously

my %sp_ext;
my %sp_ty;
my %n_ras;
my %n_vec;
my %n_t;
my %t_ty;
my %n_ag;
my %n_agrw;
my %r_agrw;
my %ag_ty;
my %soc_ty;
my %n_soc;
my %n_run;
my %n_comp;
my %yn_ras;
my %yn_vec;
my %yn_t;
my %yn_ag;
my %yn_run;
my $min_year;
my $max_year;
my %space_time;
for(my $i = 0; $i <= $#merged; $i++) {
    my $is_hpc = $merged[$i]->[$GISHPC];
    my $j = $merged2db{$i};
    my $year = $db[$j]->{'year'};
    if(!defined($min_year) || $year < $min_year) {
        $min_year = $year;
    }
    if(!defined($max_year) || $year > $max_year) {
        $max_year = $year;
    }
    $sp_ext{$is_hpc}->{$merged[$i]->[$GSPEXT]}++;
    $sp_ty{$is_hpc}->{$merged[$i]->[$GSPTY]}++;
    $space_time{$is_hpc}->{$merged[$i]->[$GSPEXT]}->{$merged[$i]->[$GSTEPTY]}++;
    $space_time{'TOTAL'}->{$merged[$i]->[$GSPEXT]}->{$merged[$i]->[$GSTEPTY]}++;
    push(@{$n_ras{$is_hpc}}, $merged[$i]->[$GSPRAS]);
    push(@{$yn_ras{$is_hpc}->{$year}}, $merged[$i]->[$GSPRAS]);
    push(@{$n_vec{$is_hpc}}, $merged[$i]->[$GSPVEC]);
    push(@{$yn_vec{$is_hpc}->{$year}}, $merged[$i]->[$GSPVEC]);
    push(@{$n_t{$is_hpc}}, $merged[$i]->[$GNSTEP]);
    push(@{$yn_t{$is_hpc}->{$year}}, $merged[$i]->[$GNSTEP]);
    $t_ty{$is_hpc}->{$merged[$i]->[$GSTEPTY]}++;
    push(@{$n_ag{$is_hpc}}, $merged[$i]->[$GNAGENT]);
    push(@{$yn_ag{$is_hpc}->{$year}}, $merged[$i]->[$GNAGENT]);
    push(@{$n_agrw{$is_hpc}}, $merged[$i]->[$GNAGRW]);
    $ag_ty{$is_hpc}->{$merged[$i]->[$GAGTY]}++;
    push(@{$n_run{$is_hpc}}, $merged[$i]->[$GNRUN]);
    push(@{$yn_run{$is_hpc}->{$year}}, $merged[$i]->[$GNRUN]);
    my @soc_ck = split(/;/, $merged[$i]->[$GSOCTY]);
    push(@{$n_soc{$is_hpc}}, scalar(@soc_ck));
    foreach my $soc (@soc_ck) {
        $soc_ty{$is_hpc}->{$soc}++;
    }
}
foreach my $env (keys(%n_ag)) {
    my $sim = $n_ag{$env};
    my $rw = $n_agrw{$env};
    my $npix = $n_ras{$env};
    my $nfeat = $n_vec{$env};
    my $ntime = $n_t{$env};
    my $nrun = $n_run{$env};

    die "BUG! $#$sim != $#$rw\n" if($#$sim != $#$rw);

    for(my $j = 0; $j <= $#$sim; $j++) {
        if($$sim[$j] =~ /\d/ && $$rw[$j] =~ /\d/) {
            push(@{$r_agrw{$env}}, $$sim[$j] / $$rw[$j]);
        }
        else {
            push(@{$r_agrw{$env}}, "NA");
        }
        if($$sim[$j] eq 'NA' && $$npix[$j] eq 'NA' && $$nfeat[$j] eq 'NA
            ' && $$ntime[$j] eq 'NA' && $$nrun[$j] eq 'NA')
        {
            push(@{$n_comp{$env}}, "NA");
        }
        else {
            my $ncomp = 1;
            $ncomp *= $$sim[$j] if($$sim[$j] =~ /\d/);
            $ncomp *= $$ntime[$j] if($$ntime[$j] =~ /\d/);
            $ncomp *= $$nrun[$j] if($$nrun[$j] =~ /\d/);

            my $nspace = 0;
            $nspace += $$npix[$j] if($$npix[$j] =~ /\d/);
            $nspace += $$nfeat[$j] if($$nfeat[$j] =~ /\d/);

            $ncomp *= $nspace if($nspace > 0);

            push(@{$n_comp{$env}}, $ncomp);
        }
    }
}

print $R_FP <<RESULTS1;
################################################################################
#
# ####   ###        #####             #####               #    ###
# #   # #   #       #                     #              ##   #   #
# ####  # # #       ####                 #                #     ##
# #   # #  ##           #               #                 #    #
# #   #  ####       ####   #           #     #           ###  #####  #
#                         #                 #                       #
#
#   #    ###                #   #####
#  ##   #   #              ##   #
#   #     ##                #   ####
#   #   #   #               #       #
#  ###   ###   #           ###  ####
#             #
#
################################################################################
RESULTS1

foreach my $bar (['Spatial Extent', '5', 'spmat', 'bar.space.scale', \%sp_ext, \&sort_space],
    ['Spatial Representation', '7', 'srmat', 'bar.space.type', \%sp_ty, \&sort_how_space],
    ['Temporal Resolution', '12', 'trmat', 'bar.time.scale', \%t_ty, \&sort_time],
    ['Finest Grain Agent Type', '15', 'fgmat', 'bar.agent.scale', \%ag_ty, \&sort_agent],
    ['Agent Types', '13', 'agmat', 'bar.agent.types', \%soc_ty, \&sort_agent])
{
    my ($title, $rq, $var, $pdf, $data, $sort) = @$bar;
    my $table_file = $parameters{'tables-rq-prefix'}."$rq $title.tex";
    $table_file =~ s/\s+/_/g;
    my $table_label = "tab:R$rq";

    my @envs = sort {
        ($a eq $b) ? 0 : (
            ($a eq "NA") ? 1 : (
                ($b eq "NA") ? -1 : ($b cmp $a)
            )
        )
    } keys(%$data);

    my %bars;
    # Make sure we have comprehensively captured all the bars
    foreach my $env (@envs) {
        foreach my $bar (keys(%{$data->{$env}})) {
            $bars{$bar}++;
        }
    }
    # Create a matrix for the bar plot
    my @matrix;
    my @row_names;
    my @col_names;
    foreach my $bar (sort { &$sort($a, $b) } keys(%bars)) {
        my $colname = $bar;
        $colname = "(Not Found)" if($colname eq "NA");

        push(@col_names, $colname);

        foreach my $env (@envs) {

            if(scalar(@col_names) == 1) {
                my $rowname = $env;
                $rowname = "(N/A)" if($rowname eq "NA");

                push(@row_names, $rowname);
            }

            if(exists($data->{$env}->{$bar})) {
                push(@matrix, $data->{$env}->{$bar});
            }
            else {
                push(@matrix, 0);
            }
        }
    }
    print $R_FP "logbook(\"Plotting barchart of \\\"$title\\\"\")\n";
    print $R_FP "$var = matrix(c(", join(", ", @matrix), "), nrow = ", scalar(@row_names),
        ", ncol = ", scalar(@col_names), ", dimnames = list(c(\"",
        join("\", \"", @row_names), "\"), c(\"", join("\", \"", @col_names), "\")))\n";
    print $R_FP "$var.t = colSums($var)\n";
    print $R_FP "$var.p = $var\n";
    print $R_FP "for(i in 1:length($var.t)) $var.p[, i] = $var.p[, i] / $var.t[i]\n";
    print $R_FP "if(plots.bw) {\n";
    print $R_FP "    horiz.bar.pdf($pdf, $var.t, colnames($var), main = \"$title\")\n";
    print $R_FP "} else if(bar.p) {\n";
    print $R_FP "    horiz.bar.pdf($pdf, $var.p, colnames($var), legend.text = TRUE, ",
        "main = \"$title (Proportions)\", col = unlist(hpc.pal), ",
        "args.legend = list(x = \"top\", horiz = TRUE, inset = -0.05, bty = \"n\"))\n";
    print $R_FP "} else {\n";
    print $R_FP "    horiz.bar.pdf($pdf, $var, colnames($var), legend.text = TRUE, ",
        "main = \"$title\", col = unlist(hpc.pal), ",
        "args.legend = list(x = \"top\", horiz = TRUE, inset = -0.05, bty = \"n\"))\n";
    print $R_FP "}\n";
    print $R_FP "$var.df = as.data.frame($var)\n";
    print $R_FP "latex_table($var.df, caption = \"Table of $title (R$rq)\", ",
        "label = \"$table_label\", file = paste0(tex.dir, \"/$table_file\"), HPC.table = TRUE, ",
        "row.totals = TRUE, col.totals = TRUE, bars = ", scalar(@merged), ", transpose = TRUE)\n";
}

warn "PROGRESS [", &iso_date(), "]: Completed time / space / agent bar charts\n";

# Combined space and time plot

print $R_FP <<SPACE_TIME;
################################################################################
#
#  #### ####   ###   #### #####       #####  ###  #   # #####
# #     #   # #   # #     #             #     #   ## ## #
#  ###  ####  ##### #     ####          #     #   # # # ####
#     # #     #   # #     #             #     #   #   # #
# ####  #     #   #  #### #####         #    ###  #   # #####
#
################################################################################
SPACE_TIME

my @space_types = sort {&sort_space($a, $b)} keys(%space_order);
my @time_types = sort {&sort_time($a, $b)} keys(%time_order);
print $R_FP "space.types <- c(\"", join("\", \"", @space_types), "\")\n";
print $R_FP "time.types <- c(\"", join("\", \"", @time_types), "\")\n";
print $R_FP "space.time <- as.data.frame(matrix(ncol = 7, nrow = length(space.types) * length(time.types)))\n";
print $R_FP "names(space.time) = c(\"space\", \"time\", \"yes\", \"no\", \"maybe\", \"empty\", \"all\")\n";
my $space_time_row = 0;
foreach my $space (@space_types) {
    foreach my $time (@time_types) {
        $space_time_row++;
        print $R_FP "space.time[$space_time_row, ] = c(\"$space\", \"$time\"";
        foreach my $env ('Yes', 'No', 'Disputed', 'NA', 'TOTAL') {
            if(exists($space_time{$env}->{$space}->{$time})) {
                print $R_FP ", ", $space_time{$env}->{$space}->{$time};
            }
            else {
                print $R_FP ", 0";
            }
        }
        print $R_FP ")\n";
    }
}
    
print $R_FP "space.time\$space = factor(space.time\$space, levels = space.types)\n";
print $R_FP "space.time\$time = factor(space.time\$time, levels = time.types)\n";
print $R_FP "st.pdf = list(yes = grid.space.time.hpc, no = grid.space.time.pc, ",
    "maybe = grid.space.time.maybe, empty = grid.space.time.na, all = grid.space.time.all)\n";
print $R_FP "for(env in names(hpc.pal)) {\n";
print $R_FP "    logbook(\"Plotting space-time graph for \", env)\n";
print $R_FP "    pdf(st.pdf[[env]])\n";
print $R_FP "    p = ggplot(space.time, aes(x = space, y = time, fill = ",
    "as.numeric(space.time[, env]))) + geom_tile() ",
    "+ scale_fill_gradient(low = \"white\", high = hpc.pal[[env]]) + ",
    "theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1), ",
    "legend.title = element_blank())\n";
print $R_FP "    print(p)  # thanks stack overflow (sigh)\n";
print $R_FP "    dev.off()\n";
print $R_FP "}\n";

print $R_FP <<RESULTS2;
################################################################################
#
# ####   ###         ###                #    ###                #     #
# #   # #   #       #   #              ##   #  ##              ##    ##
# ####  # # #        ####               #   # # #               #     #
# #   # #  ##           #               #   ##  #               #     #
# #   #  ####        ###   #           ###   ###   #           ###   ###   #
#                         #                       #                       #
#
#   #      #                #    ###                #   #####
#  ##     #                ##   #                  ##       #         #
#   #    # #                #   ####                #      #         ###
#   #   #####               #   #   #               #     #           #
#  ###     #   #           ###   ###   #           ###   #
#             #                       #
#
################################################################################
RESULTS2

# These are not 'proper' histograms, note.

foreach my $hist (['Numbers of Pixels', '9', 'pixmat', 'hist.space.size.px', \%n_ras, 1],
    ['Numbers of Features', '10', 'vecmat', 'hist.space.size.ft', \%n_vec, 1],
    ['Numbers of Time Steps', '11', 'tmat', 'hist.time.size', \%n_t, 1],
    ['Numbers of Agents', '14', 'nagmat', 'hist.agent.size', \%n_ag, 1],
    ['Ratio of N. Agents to N. Real World', '14over16', 'rwrat', 'hist.agent.ratio', \%r_agrw, 1],
    ['Numbers of Runs', '17', 'nrun', 'hist.runs', \%n_run, 1],
    ['Numbers of Types of Agent', 'agty', 'nagty', 'hist.agent.types', \%n_soc, 0],
    ['Estimated Computing Scale', 'comp', 'comp', 'hist.comp', \%n_comp, 1])
{
    my ($title, $rq, $var, $pdf, $data, $do_log) = @$hist;
    my $table_file = $parameters{'tables-rq-prefix'}."$rq $title.tex";
    $table_file =~ s/\s+/_/g;
    my $table_label = "tab:R$rq";

    my %matrix;
    my @row_names;
    my $min_log;
    my $max_log;
    my $any_na = 0;

    my @envs = sort {
        ($a eq $b) ? 0 : (
            ($a eq "NA") ? 1 : (
                ($b eq "NA") ? -1 : ($b cmp $a)
            )
        )
    } keys(%$data);


    foreach my $env (@envs) {
        my $rowname = $env;
        $rowname = "(N/A)" if($rowname eq "NA");
        push(@row_names, $rowname);

        foreach my $datum (@{$$data{$env}}) {
            if($datum !~ /\d/) {
                $matrix{$env}->{'NA'}++;
                $any_na = 1;
            }
            elsif($do_log) {
                my $log = int(log($datum) / log(10));
                if(!defined($min_log) || $log < $min_log) {
                    $min_log = $log;
                }
                if(!defined($max_log) || $log > $max_log) {
                    $max_log = $log;
                }
                $matrix{$env}->{$log}++;
            }
            else {
                $matrix{$env}->{$datum}++;
                if(!defined($min_log) || $datum < $min_log) {
                    $min_log = $datum;
                }
                if(!defined($max_log) || $datum > $max_log) {
                    $max_log = $datum;
                }
            }
        }
    }

    my @col_names;
    for(my $i = $min_log; $i <= $max_log; $i++) {
        push(@col_names, $i);
    }
    push(@col_names, "(No Data)") if($any_na);
    my @mat;

    foreach my $env (@envs) {
        for(my $i = $min_log; $i <= $max_log; $i++) {
            if(exists($matrix{$env}->{$i})) {
                push(@mat, $matrix{$env}->{$i});
            }
            else {
                push(@mat, 0);
            }
        }
        if($any_na) {
            if(exists($matrix{$env}->{'NA'})) {
                push(@mat, $matrix{$env}->{'NA'});
            }
            else {
                push(@mat, 0);
            }
        }
    }

    print $R_FP "logbook(\"Plotting 'histogram' of \\\"$title\\\"\")\n";

    print $R_FP "$var = matrix(c(", join(", ", @mat), "), nrow = ", scalar(@row_names),
        ", ncol = ", scalar(@col_names), ", byrow = TRUE, dimnames = list(c(\"",
        join("\", \"", @row_names), "\"), c(\"", join("\", \"", @col_names), "\")))\n";
    print $R_FP "$var.t = colSums($var)\n";

    print $R_FP "if(plots.bw) {\n";
    print $R_FP "    vert.bar.pdf($pdf, $var.t, colnames($var), space = 0, border = NA, ",
        "main = \"$title\", xlab = ",
            ($do_log ? "TeX(\"\$\\\\lfloor \\\\log_{10} x \\\\rfloor\$\")" : "\"$title\""),
        ")\n";

    print $R_FP "} else {\n";
    print $R_FP "    vert.bar.pdf($pdf, $var, colnames($var), legend.text = TRUE, space = 0, ",
        "border = NA, main = \"$title\", xlab = ",
            ($do_log ? "TeX(\"\$\\\\lfloor \\\\log_{10} x \\\\rfloor\$\")" : "\"$title\""),
        ", args.legend = list(title = \"HPC?\", horiz = TRUE, x = \"top\", inset = -0.05, ",
        "bty = \"n\"), col = unlist(hpc.pal))\n";
    print $R_FP "}\n";

    if($do_log) {
        print $R_FP "colnos = $min_log:$max_log\n";
        print $R_FP "colnames($var)[1:length(colnos)] = paste0(\"\$[10{^\", colnos, \"}, 10^{\", ",
            "colnos + 1, \"}[\$\")\n";
    }
    print $R_FP "latex_table(as.data.frame($var), caption = \"Table of $title (R$rq)\", ",
        "label = \"$table_label\", file = paste0(tex.dir, \"/$table_file\"), transpose = TRUE, ",
        "row.totals = TRUE, col.totals = TRUE, HPC.table = TRUE, bars = ", scalar(@merged), ")\n";
}

warn "PROGRESS [", &iso_date(), "]: Completed computing demand histograms\n";

print $R_FP <<TIME_SERIES;
################################################################################
#
# #####  ###  #   # #####        #### ##### ####   ###  #####  ####
#   #     #   ## ## #           #     #     #   #   #   #     #
#   #     #   # # # ####         ###  ####  ####    #   ####   ###
#   #     #   #   # #               # #     #   #   #   #         #
#   #    ###  #   # #####       ####  ##### #   #  ###  ##### ####
#
################################################################################
TIME_SERIES

foreach my $ts (['Numbers of Pixels', 'ts.pix', 'ts.space.size.px', \%yn_ras],
    ['Numbers of Features', 'ts.feat', 'ts.space.size.ft', \%yn_vec],
    ['Numbers of Time Steps', 'ts.step', 'ts.time.size', \%yn_t],
    ['Numbers of Agents', 'ts.agent', 'ts.agent.size', \%yn_ag],
    ['Numbers of Runs', 'ts.run', 'ts.runs', \%yn_run])
{
    my ($title, $var, $pdf, $data) = @$ts;

    my @years = $min_year..($max_year);
    my %mins;
    my %maxes;
    my $maxmax;

    my @envs = sort {
        ($a eq $b) ? 0 : (
            ($a eq "NA") ? 1 : (
                ($b eq "NA") ? -1 : ($b cmp $a)
            )
        )
    } keys(%$data);

    my @totals;
    foreach my $env (@envs) {
        foreach my $year (@years) {
            if(exists($data->{$env}->{$year})) {
                my $min;
                my $max;
                foreach my $datum (@{$data->{$env}->{$year}}) {
                    next if($datum !~ /\d/);
                    push(@totals, [$year, $env, $datum]);

                    if(!defined($min) || $datum < $min) {
                        $min = $datum;
                    }
                    if(!defined($max) || $datum > $max) {
                        $max = $datum;
                    }
                    if(!defined($maxmax) || $datum > $maxmax) {
                        $maxmax = $datum;
                    }
                }
                $min = "NA" if(!defined($min));
                $max = "NA" if(!defined($max));
                push(@{$mins{$env}}, $min);
                push(@{$maxes{$env}}, $max);
            }
            else {
                push(@{$mins{$env}}, "NA");
                push(@{$maxes{$env}}, "NA");
            }
        }
    }

    print $R_FP "logbook(\"Plotting time series of \\\"$title\\\"\")\n";

    print $R_FP "df.$var = as.data.frame(matrix(ncol = 3, nrow = ", scalar(@totals), "))\n";
    print $R_FP "names(df.$var) = c(\"year\", \"env\", \"n\")\n";
    print $R_FP "df.$var\$year = c(", join(", ", map { $_->[0] } @totals), ")\n";
    print $R_FP "df.$var\$env = c(\"", join("\", \"", map { $_->[1] } @totals), "\")\n";
    print $R_FP "df.$var\$n = c(", join(", ", map { $_->[2] } @totals), ")\n";

    print $R_FP "pdf($pdf, width = 9, height = 6)\n";
    print $R_FP "if(plots.bw) {\n";
    print $R_FP "    boxplot(log10(df.$var\$n) ~ df.$var\$year, main = \"$title\", ",
        "xlab = \"Year of Publication\", ylab = \"log(Number)\", las = 2)\n";
    print $R_FP "} else {\n";
    for(my $i = 0; $i <= $#envs; $i++) {
        print $R_FP "    df.$var.$i = as.data.frame(matrix(ncol = 3, nrow = ", scalar(@years), "))\n";
        print $R_FP "    names(df.$var.$i) = c(\"year\", \"minima\", \"maxima\")\n";
        print $R_FP "    df.$var.$i\$year = $min_year:$max_year\n";
        print $R_FP "    for(y in unique(df.$var\$year)) {\n";
        print $R_FP "        yy = which(df.$var.$i\$year == y)\n";
        print $R_FP "        subdf = subset(df.$var, year == y)\n";
        print $R_FP "        df.$var.$i\$minima[yy] = min(subdf\$n)\n";
        print $R_FP "        df.$var.$i\$maxima[yy] = max(subdf\$n)\n";
        print $R_FP "    }\n";
    }
    print $R_FP "    plot(0.15 + df.$var.$#envs\$years, df.$var.$#envs\$maxima, pch = 19, ",
        "xlim = c($min_year - 0.5, $max_year + 0.5), ylim = c(1, max(df.$var\$n) * 10), ",
        "main = \"$title\", xlab = \"Year of Publication\", ylab = \"Number\", ",
        "log = \"y\", col = hpc.pal[[", scalar(@envs), "]])\n";
    print $R_FP "    points(0.15 + df.$var.$#envs\$years, df.$var.$#envs\$minima, pch = 19, ",
        "col = hpc.pal[[", scalar(@envs), "]])\n";
    print $R_FP "    for(i in 1:length(df.$var.$#envs\$years)) {\n",
        "        if(!is.na(df.$var.$#envs\$minima[i])) {\n",
        "            lines(rep(0.15 + df.$var.$#envs\$years[i], 2), ",
        "c(df.$var.$#envs\$minima[i], df.$var.$#envs\$maxima[i]), ",
        "col = hpc.pal[[", scalar(@envs), "]])\n        }\n    }\n";
    for(my $i = 0; $i < $#envs; $i++) {
        my $c = $i + 1;
        my $off = -0.15 + (0.1 * $i);
        foreach my $end ('minima', 'maxima') {
            print $R_FP "    points($off + df.$var.$i\$years, df.$var.$i\$$end, pch = 19, ",
                "col = hpc.pal[[$c]])\n";
        }
        print $R_FP "    for(i in 1:length(df.$var.$i\$years)) {\n",
            "        if(!is.na(df.$var.$i\$minima[i])) {\n",
            "            lines(rep($off + df.$var.$i\$years[i], 2), ",
            "c(df.$var.$i\$minima[i], df.$var.$i\$maxima[i]), ",
            "col = hpc.pal[[$c]])\n        }\n    }\n";
    }
    print $R_FP "    legend(\"top\", legend = c(\"", join("\", \"", @envs), 
        "\"), col = unlist(hpc.pal), pch = 16, title = \"HPC?\", horiz = TRUE, inset = -0.05, ",
        "bty = \"n\")\n";
    print $R_FP "}\ndev.off()\n";
}

warn "PROGRESS [", &iso_date(), "]: Completed computing demand time series\n";

# 10. Summaries of limitations (RQ 21, 22)

print $R_FP <<RESULTS3;
################################################################################
#
# ####   ###         ###    #                ###   ###
# #   # #   #       #   #  ##               #   # #   #
# ####  # # #         ##    #                 ##    ##
# #   # #  ##        #      #                #     #
# #   #  ####       #####  ###   #          ##### #####
#                               #
#
################################################################################
RESULTS3

my %lim_bool;
my %all_bool;
my %lim_phr;
my %lim_ty;

for(my $i = 0; $i <= $#merged; $i++) {
    my $is_hpc = $merged[$i]->[$GISHPC];

    $lim_bool{$is_hpc}->{$merged[$i]->[$GISCOMPLIM]}++;
    $all_bool{$merged[$i]->[$GISCOMPLIM]}++;

    my @phr = split(/;/, $merged[$i]->[$GLIMPHR]);
    foreach my $ph (@phr) {
        if(exists($glimphr_map{$ph})) {
            $ph = $glimphr_map{$ph};
        }
        $lim_phr{$is_hpc}->{$ph}++;
    }

    my @typ = split(/;/, $merged[$i]->[$GLIMTY]);
    foreach my $ty (@typ) {
        if(exists($glimty_map{$ty})) {
            $ty = $glimty_map{$ty};
        }
        $lim_ty{$is_hpc}->{$ty}++;
    }
}

my @is_hpc = sort {
    ($a eq $b) ? 0 : (
        ($a eq "NA") ? 1 : (
            ($b eq "NA") ? -1 : ($b cmp $a)
        )
    )
} keys(%lim_bool);
my @is_lim = sort {
    ($a eq $b) ? 0 : (
        ($a eq "NA") ? -1 : (
            ($b eq "NA") ? 1 : ($b cmp $a)
        )
    )
} keys(%all_bool);

print $R_FP "limmat = matrix(c(";
my $lim_first = 1;
foreach my $lim (@is_lim) {
    foreach my $env (@is_hpc) {
        if($lim_first) {
            $lim_first = 0;
        }
        else {
            print $R_FP ", ";
        }
        print $R_FP (exists($lim_bool{$env}->{$lim})) ? $lim_bool{$env}->{$lim} : 0;
    }
}
print $R_FP "), nrow = ", scalar(@is_hpc), ", ncol = ", scalar(@is_lim),
    ", dimnames = list(c(\"", join("\", \"", @is_hpc), "\"), c(\"",
    join("\", \"", @is_lim), "\")))\n";
print $R_FP "limmat.t = colSums(limmat)\n";
print $R_FP "if(plots.bw) {\n";
print $R_FP "    horiz.bar.pdf(bar.limits, limmat.t, colnames(limmat), ",
    "main = \"Practical Limitations?\")\n";
print $R_FP "} else {\n";
print $R_FP "    horiz.bar.pdf(bar.limits, limmat, colnames(limmat), legend.text = TRUE, ",
    "main = \"Practical Limitations?\", col = unlist(hpc.pal))\n";
print $R_FP "}\n";

foreach my $ckbox (
    ['Limitations in Model Structure', 'limty', 'bar.limits.model', 21, \%lim_ty],
    ['Limitations for Future Work', 'limphr', 'bar.limits.future', 22, \%lim_phr]
) {
    my ($title, $var, $pdf, $rq, $data) = @$ckbox;
    my $table_file = $parameters{'tables-rq-prefix'}."$rq $title.tex";
    $table_file =~ s/\s+/_/g;
    my $table_label = "tab:R$rq";

    my @envs = sort {
        ($a eq $b) ? 0 : (
            ($a eq "NA") ? 1 : (
                ($b eq "NA") ? -1 : ($b cmp $a)
            )
        )
    } keys(%$data);

    my %bars;
    # Make sure we have comprehensively captured all the bars
    foreach my $env (@envs) {
        foreach my $bar (keys(%{$data->{$env}})) {
            $bars{$bar}++;
        }
    }
    # Create a matrix for the bar plot
    my @matrix;
    my @row_names;
    my @col_names;
    foreach my $bar (sort {
        ($a eq $b) ? 0 : (
            ($a eq "NA") ? -1 : (
                ($b eq "NA") ? 1 : ($b cmp $a)
            )
        )
    } keys(%bars)) {
        my $colname = $bar;
        $colname = "(None)" if($colname eq "NA");

        push(@col_names, $colname);

        foreach my $env (@envs) {

            if(scalar(@col_names) == 1) {
                my $rowname = $env;
                $rowname = "(N/A)" if($rowname eq "NA");

                push(@row_names, $rowname);
            }

            if(exists($data->{$env}->{$bar})) {
                push(@matrix, $data->{$env}->{$bar});
            }
            else {
                push(@matrix, 0);
            }
        }
    }
    print $R_FP "logbook(\"Plotting barchart of \\\"$title\\\"\")\n";
    print $R_FP "$var = matrix(c(", join(", ", @matrix), "), nrow = ", scalar(@row_names),
        ", ncol = ", scalar(@col_names), ", dimnames = list(c(\"",
        join("\", \"", @row_names), "\"), c(\"", join("\", \"", @col_names), "\")))\n";
    print $R_FP "$var.t = colSums($var)\n";
    print $R_FP "if(plots.bw) {\n";
    print $R_FP "    horiz.bar.pdf($pdf, $var.t, colnames($var), main = \"$title\")\n";
    print $R_FP "} else {\n";
    print $R_FP "    horiz.bar.pdf($pdf, $var, colnames($var), legend.text = TRUE, ",
        "main = \"$title\", col = unlist(hpc.pal), ",
        "args.legend = list(title = \"HPC?\", horiz = TRUE, x = \"top\", inset = -0.05, ",
        "bty = \"n\"))\n";
    print $R_FP "}\n";
    print $R_FP "latex_table(as.data.frame($var), caption = \"$title (R$rq)\", ",
        "label = \"$table_label\", file = paste0(tex.dir, \"/$table_file\"), transpose = TRUE, ",
        "row.totals = TRUE, col.totals = TRUE, HPC.table = TRUE, bars = max($var.t))\n";

}

warn "PROGRESS [", &iso_date(), "]: Completed bar charts of limitations\n";

# 11. Classification of Q1, Q2 and Q3 against search strings, ASJC,
#     classes, and journal sources

print $R_FP <<DATA_CSV;
################################################################################
#
#  ###    #          ###        ####   ###  #####  ###
# #   #  ##         #   #       #   # #   #   #   #   #
# # # #   #    ###    ##        #   # #####   #   #####
# #  ##   #         #   #       #   # #   #   #   #   #
#  ####  ###         ###        ####  #   #   #   #   #
#
################################################################################
DATA_CSV

my @uscr = sort { $a <=> $b } keys(%db2scrres);
print $R_FP "scrres = data.frame(id = c(", join(", ", @uscr) ,")";
foreach my $alymin (["all", 3], ["any", 1]) {
    my $aly = $$alymin[0];
    my $min = $$alymin[1];
    foreach my $varq (["abm", $S_Q1], ["soc", $S_Q2], ["emp", $S_Q3]) {
        my $var = $$varq[0];
        my $q = $$varq[1];
        print $R_FP ",\n\t$aly.$var = c(", join(", ",
            map { $scrres[$db2scrres{$_}]->[$q] >= $min ? "T" : "F" } @uscr), ")";
    }
}
print $R_FP ")\n";
foreach my $var ("abm", "soc", "emp") {
    print $R_FP "scrres\$disp.$var = scrres\$any.$var & !scrres\$all.$var\n";
}
print $R_FP "scrres\$\`in\` = scrres\$all.abm & scrres\$all.soc & scrres\$all.emp\n";
print $R_FP "scrres\$assigned = c(", join(", ",
    map { exists($db2assign{$_}) ? "T" : "F" } @uscr), ")\n";

my @uass = map { exists($db2assign{$_}) ? $db2assign{$_} : -1 } @uscr;
my @uasq = map { $_ >= 0 ? [ &aq123($assign[$_], \@review) ] : [ "NA", "NA", "NA" ] } @uass;

foreach my $varq (["abm", 0], ["soc", 1], ["emp", 2]) {
    my $var = $$varq[0];
    my $q = $$varq[1];
    print $R_FP "scrres\$is.$var.rev = c(", join(", ",
        map { $_->[$q] eq "Yes" ? "T" : ($_->[$q] eq "No" ? "F" : "NA") } @uasq), ")\n";
    print $R_FP "scrres\$disp.$var.rev = c(", join(", ",
        map { $_->[$q] eq "Disputed" ? "T" : ($_->[$q] eq "NA" ? "NA" : "F") } @uasq), ")\n";
}
print $R_FP "scrres\$in.rev = scrres\$is.abm.rev & scrres\$is.soc.rev & scrres\$is.emp.rev\n";
print $R_FP "scrres\$reviewed = c(", join(", ",
    map { exists($db2merged{$_}) ? "T" : "F" } @uscr), ")\n";

foreach my $topic (sort {&sort_topics($a, $b)} keys(%all_topics)) {
    print $R_FP "scrres\$\`$topic\` = c(", join(", ",
        map { exists($db[$_]->{'__topics_intent'}->{$topic}) ? "T" : "F" } @uscr), ")\n";
}
foreach my $asjc_cat (sort {&sort_asjc($a, $b)} keys(%asjc_n)) {
    next if($asjc_cat eq '(None)');
    my $scat = $short_scats{$asjc_cat};
    print $R_FP "scrres\$\`$scat\` = c(", join(", ",
        map { exists($db[$_]->{'__asjc_cats'}->{$asjc_cat}) ? "T" : "F" } @uscr), ")\n";
}
print $R_FP "scrres\$journal = c(\"", join("\", \"",
    map { exists($shortj{$db[$_]->{'__source'}})
        ? $shortj{$db[$_]->{'__source'}} : "Other" }
    @uscr), "\")\n";

print $R_FP "write.csv(scrres, data.screening, row.names = FALSE)\n";

if($parameters{'R-do-table-mi'}) {
    print $R_FP <<MUT_INF;
################################################################################
#
# #   # #   # ##### #   #  ###  #            ###  #   # #####  ###
# ## ## #   #   #   #   # #   # #             #   ##  # #     #   #
# # # # #   #   #   #   # ##### #             #   # # # ####  #   #
# #   # #   #   #   #   # #   # #             #   #  ## #     #   #
# #   #  ###    #    ###  #   # #####        ###  #   # #      ###
#
################################################################################
MUT_INF
    my $topic_str = "\"".(join("\", \"", sort {$a cmp $b} keys(%all_topics)))."\"";
    print $R_FP "logbook(\"Plotting mutual information\")\n";
    print $R_FP "pdf(bar.mutinfs)\n";
    print $R_FP "mint(scrres, \"all.abm\", c($topic_str), \"Mutual information \$I\$ ",
        "between unanimously agreed screening classification and topics.\", \"tab:",
        "screen-all\", \"Mutual Information (unanimous)\", file = table.mi.all)\n";

    print $R_FP "logbook(\"Plotting mutual information (any)\")\n";
    print $R_FP "mint(scrres, \"any.abm\", c($topic_str), \"Mutual information \$I\$ ",
        "between positive screening classification by anyone and topics.\", \"tab:",
        "screen-any\", \"Mutual Information (at least one)\", file = table.mi.any)\n";

    print $R_FP "logbook(\"Plotting mutual information (JASSS)\")\n";
    print $R_FP "mint(subset(scrres, journal == \"JASSS\"), ",
        "\"all.abm\", c($topic_str), \"Mutual information \$I\$ ",
        "between unanimously agreed screening classification and topics for screened ",
        "articles in \\\\textit{JASSS}.\", \"tab:",
        "screen-all-jasss\", \"Mutual Information (JASSS)\", file = table.mi.jasss)\n";

    print $R_FP "logbook(\"Plotting mutual information (assigned)\")\n";
    print $R_FP "mint(subset(scrres, assigned), ",
        "\"is.abm.rev\", c($topic_str), \"Mutual information \$I\$ ",
        "between unanimously agreed screening classification and topics for screened ",
        "articles assigned for review.\", \"tab:",
        "screen-all-assigned\", \"Mutual Information (Reviewed)\", file = table.mi.review)\n";

    print $R_FP "dev.off()\n";
    warn "PROGRESS [", &iso_date(), "]: Completed Mutual Information analysis\n";
}

# 12. Ditto for mentions of and types of computing resource used

print $R_FP <<RESULTS4;
################################################################################
#
# ####   ###          #    ###
# #   # #   #        ##   #   #
# ####  # # #         #    ####
# #   # #  ##         #       #
# #   #  ####        ###   ###
#
################################################################################
RESULTS4

my %compty;
my %compty_col = ('ALL' => 'hpc.pal$all');
my %affil;
my %affil_ctry;
for(my $i = 0; $i <= $#merged; $i++) {
    $compty{$merged[$i]->[$GCOMPTY]}++;
    my $j = $merged2db{$i};
    my $ctry = '(None Found)';
    if(exists($db[$j]->{'affiliation'})) {
        my $txt = $db[$j]->{'affiliation'};
        if($txt =~ /\(Corresponding Author\).*,\s*([^,;.]+)\./) {
            $ctry = $1;
        }
        elsif($txt =~ /\(Corresponding Author\)[^.]*,\s*([^,;.]+)\./) {
            $ctry = $1;
        }
        elsif($txt =~ /;[^.;]+,\s*([^,;.]+)\./) {
            $ctry = $1;
        }
        elsif($txt =~ /^[^.;]+,\s*([^,;.]+)\./) {
            $ctry = $1;
        }
        else {
            &logbook("Could not extract a country from affiliation \"$txt\"");
        }
    }
    if($ctry ne '(None Found)') {
        # Handle some known cases from log files
        $ctry = 'USA' if($ctry =~ /^[A-Z][A-Z]\s+(\d\d\d\d\d\s+)?USA$/);
        $ctry = 'China' if($ctry eq 'Peoples R China');
        $ctry = 'UK' if($ctry eq 'England' || $ctry eq 'Scotland' || $ctry eq 'North Ireland');
        $ctry = 'United Arab Emirates' if($ctry eq 'U Arab Emirates');

        $affil_ctry{$merged[$i]->[$GISHPC]}->{$ctry}++;
        $affil_ctry{'ALL'}->{$ctry}++;
    }
    if($merged[$i]->[$GISHPC] eq 'Yes') {
        $compty_col{$merged[$i]->[$GCOMPTY]} = 'hpc.pal$yes';
        if(exists($db[$j]->{'affiliations'})) {
            my @affs = split(/;\s*/, $db[$j]->{'affiliations'});
            foreach my $aff (@affs) {
                if($aff =~ /,/) {
                    $aff = (split(/,/, $aff))[0];
                }
                $aff =~ s/\\//g;

                $affil{$aff}++;
            }
        }
        else {
            $affil{'(None Found)'}++;
        }
    }
    elsif($merged[$i]->[$GISHPC] eq 'No') {
        $compty_col{$merged[$i]->[$GCOMPTY]} = 'hpc.pal$no';
    }
    elsif($merged[$i]->[$GISHPC] eq 'Maybe') {
        $compty_col{$merged[$i]->[$GCOMPTY]} = 'hpc.pal$maybe';
    }
    elsif($merged[$i]->[$GISHPC] eq 'NA') {
        $compty_col{$merged[$i]->[$GCOMPTY]} = 'hpc.pal$empty';
    }
}

my @comps = sort {$compty{$b} <=> $compty{$a}} keys(%compty);

print $R_FP "comps = c(", join(", ", map { $compty{$_} } @comps), ")\n";
print $R_FP "comptys = c(\"", join("\", \"", @comps), "\")\n";
print $R_FP "if(plots.bw) {\n";
print $R_FP "  horiz.bar.pdf(bar.comp, data = comps, names = comptys, ",
    "main = \"Computing Environments\")\n";
print $R_FP "} else {\n";
print $R_FP "  horiz.bar.pdf(bar.comp, data = comps, names = comptys, ",
    "col = c(", join(", ", map { $compty_col{$_} } @comps), "), ",
    "main = \"Computing Environments\")\n";
print $R_FP "}\n";
print $R_FP "latex_table(data.frame(`Computing Environments` = comptys, ",
    "Counts = comps, check.names = FALSE), caption = \"Computing Environments (R19)\", ",
    "label = \"tab:R19\", file = paste0(tex.dir, \"/R19_Computing_Environments.tex\"), ",
    "bars = max(comps))\n";


my @affils = sort {$affil{$b} <=> $affil{$a}} keys(%affil);
print $R_FP "affil = data.frame(affil = c(\"", join("\", \"", @affils), "\"), ",
    "n = c(", join(", ", map { $affil{$_} } @affils), "))\n";
print $R_FP "horiz.bar.pdf(bar.org.hpc, data = affil\$n, names = affil\$affil, ",
    "main = \"Affiliations of Corresponding Author\")\n";

# World maps

print $R_FP <<WORLD_MAPS;
################################################################################
#
# #   #  ###  ####  #     ####        #   #  ###  ####   ####
# #   # #   # #   # #     #   #       ## ## #   # #   # #
# # # # #   # ####  #     #   #       # # # ##### ####   ###
# # # # #   # #   # #     #   #       #   # #   # #         #
#  # #   ###  #   # ##### ####        #   # #   # #     ####
#
################################################################################
WORLD_MAPS

print $R_FP "world = map_data(\"world\")\n";
print $R_FP "world = world[world\$region != \"Antarctica\", ]\n";
print $R_FP "countries = unique(world\$region)\n";
print $R_FP "for(hpc in c(\"No\", \"Yes\", \"ALL\")) world[, hpc] = NA\n";
foreach my $map (['No', 'map.affil.pc'], ['Yes', 'map.affil.hpc'], ['ALL', 'map.affil.all']) {
    my ($comp, $file) = @$map;
    if(exists($affil_ctry{$comp})) {
        foreach my $ctry (keys(%{$affil_ctry{$comp}})) {
            print $R_FP "if(\"$ctry\" \%in\% countries) {\n";
            print $R_FP "  world\$`$comp`[world\$region == \"$ctry\"] = ",
                $affil_ctry{$comp}->{$ctry}, "\n}";
            if($comp eq 'ALL') {
                print $R_FP " else {\n";
                print $R_FP "  logbook(\"Country \\\"$ctry\\\" not found\")\n}";
            }
            print $R_FP "\n";
        }
        print $R_FP "pdf($file, width = 9, height = 5)\n";
        print $R_FP "ggplot() + geom_map(data = world, map = world,\n";
        print $R_FP "  aes(long, lat, map_id = region, fill = `$comp`),\n";
        print $R_FP "  color = \"white\", linewidth = 0.1) + scale_fill_gradient(\n";
        print $R_FP "  low = \"#d0d0f8\", high = hpc.pal[[\"", lc($comp), "\"]]) + theme_void(\n";
        print $R_FP "  ) + theme(legend.title = element_blank())\n";
        print $R_FP "dev.off()\n";
    }
}

my %case_ctry;
print $R_FP "pdf(map.case.all, width = 9, height = 5)\n";
for(my $i = 0; $i <= $#merged; $i++) {
    my $ctry = $merged[$i]->[$GSPNAM];
    my %ctries;
    foreach my $ctry_txt (keys(%gspnam_ctry)) {
        if($ctry =~ /\b$ctry_txt\b/) {
            foreach my $ctry_nam (@{$gspnam_ctry{$ctry_txt}}) {
                $ctries{$ctry_nam} = 1;
            }
        }
    }
    my @map_ctry = keys(%ctries);
    if(scalar(@map_ctry) == 0) {
        &logbook("No country found in GSPNAM element \"$ctry\"");
    }
    else {
        &logbook("Found \"", join("\", \"", @map_ctry), "\" in GSPNAM element \"$ctry\"");
        foreach my $mapc (@map_ctry) {
            $case_ctry{$mapc}++;
        }
    }
}
foreach my $ctry (keys(%case_ctry)) {
    print $R_FP "if(\"$ctry\" \%in\% countries) {\n";
    print $R_FP "  world\$case[world\$region == \"$ctry\"] = ",
        $case_ctry{$ctry}, "\n";
    print $R_FP "} else {\n";
    print $R_FP "  logbook(\"Case study country \\\"$ctry\\\" not found\")\n";
    print $R_FP "}\n";
}
print $R_FP "ggplot() + geom_map(data = world, map = world,\n";
print $R_FP "  aes(long, lat, map_id = region, fill = case),\n";
print $R_FP "  color = \"white\", linewidth = 0.1) + scale_fill_gradient(\n";
print $R_FP "  low = \"#d0d0f8\", high = \"#202048\") + theme_void(\n";
print $R_FP "  ) + theme(legend.title = element_blank())\n";

print $R_FP "dev.off()\nq(status = 0)\n";
close $R_FP;

warn "PROGRESS [", &iso_date(), "]: Saving bibliography\n";

my ($merged_fp, $screen_fp, $review_fp, $interest_fp);
open($merged_fp, ">:encoding(UTF-8)", $output_files{'R-merged-bib'})
    or die "Cannot create merged bib file \"", $output_files{'R-merged-bib'}, "\": $!\n";
open($screen_fp, ">:encoding(UTF-8)", $output_files{'R-screen-bib'})
    or die "Cannot create screened bib file \"", $output_files{'R-screen-bib'}, "\": $!\n";
open($review_fp, ">:encoding(UTF-8)", $output_files{'R-review-bib'})
    or die "Cannot create reviewed bib file \"", $output_files{'R-review-bib'}, "\": $!\n";
open($interest_fp, ">:encoding(UTF-8)", $output_files{'R-interest-bib'})
    or die "Cannot create interesting bib file \"", $output_files{'R-interest-bib'}, "\": $!\n";

my $n_merged_ok = 0;
my $n_review_ok = 0;
my $n_screen_ok = 0;
my $n_review_not_screen = 0;
my $n_merged_not_screen = 0;
my $n_merged_not_review = 0;
for(my $i = 0; $i <= $#db; $i++) {
    if(exists($db2screen{$i})) {
        $n_screen_ok++;
        &print_bibtex($screen_fp, $db[$i]);
        if(exists($db2assign{$i})) {
            $n_review_ok++;
            &print_bibtex($review_fp, $db[$i]);
            if(exists($db2merged{$i})) {
                $n_merged_ok++;
                &print_bibtex($merged_fp, $db[$i]);
            }
        }
        elsif(exists($db2merged{$i})) {
            $n_merged_not_review++;
            &print_bibtex($merged_fp, $db[$i]);
            &logbook("DB paper $i is linked to screen paper ", $db2screen{$i},
                " and merged paper ", $db2merged{$i}, ", but not to a review paper");
        }
    }
    elsif(exists($db2assign{$i})) {
        $n_review_not_screen++;
        &print_bibtex($review_fp, $db[$i]);
        if(exists($db2merged{$i})) {
            $n_merged_not_screen++;
            &print_bibtex($merged_fp, $db[$i]);
            &logbook("DB paper $i is linked to review paper ", $db2assign{$i},
                " and merged paper ", $db2merged{$i}, ", but not to a screen paper");
        }
        else {
            &logbook("DB paper $i is linked to review paper ", $db2assign{$i},
                " but not to a screen paper");
        }
    }
    elsif(exists($db2merged{$i})) {
        $n_merged_not_screen++;
        $n_merged_not_review++;
        &print_bibtex($merged_fp, $db[$i]);
        &logbook("DB paper $i is linked to merged paper ", $db2merged{$i},
            " but not to a screen or review paper");
    }

    if(exists($db2merged{$i})) {
        my $j = $db2merged{$i};
        if($merged[$j]->[$GISINT] eq 'Yes' || $merged[$j]->[$GISINT] eq 'Maybe') {
            &print_bibtex($interest_fp, $db[$i]);
        }
    }
}
close($review_fp);
close($screen_fp);
close($merged_fp);

warn "Screen OK: $n_screen_ok\nReview OK: $n_review_ok\nMerged OK: $n_merged_ok\n";
warn "Reviewed but not screened: $n_review_not_screen\n";
warn "Merged but not screened: $n_merged_not_screen\n";
warn "Merged but not reviewed: $n_merged_not_review\n";

warn "PROGRESS [", &iso_date(), "]: Finished\n";

close($log_fp) if defined($log_fp);

exit 0;

#######################################################################################
#                                                                                     #
#     ### #         ###                                                               #
#   ##  ###          ##                                                               #
#   #    ##          ##                                                               #
#  #     ##          ##                                    ##                         #
#  #      #          ##                                    ##                         #
#  #                 ##                                    ##                         #
#  #                 ##                              ##                               #
#  ##                ##                              ##                               #
#  ####              ##                              ##                               #
#   #####   ###  ### ## ##  ###  ##    ###  ###  #######  ### ### ###    ##     ### # #
#   ######   ##   ## ### ##  ## ###   #  ##  ##   ## ##    ##  ######   #  ##  #  ### #
#    #####   ##   ## ##   ## ####### ##   #  ##   ## ##    ##  ##   ## ##   #  #   ## #
#      ####  ##   ## ##   ## ##  ### #    ## ##   ## ##    ##  ##   ## #    ####      #
#        ##  ##   ## ##   ## ##   #  #    ## ##   ## ##    ##  ##   ## #    #####     #
#        ### ##   ## ##   ## ##     ##    ## ##   ## ##    ##  ##   ####    ## ####   #
#         ## ##   ## ##   ## ##     ##    ## ##   ## ##    ##  ##   ########## ###### #
#         ## ##   ## ##   ## ##     ##    ## ##   ## ##    ##  ##   ####        ##### #
#         ## ##   ## ##   ## ##     ##    ## ##   ## ##    ##  ##   ####           ## #
# #       #  ##   ## ##   ## ##      #    ## ##   ## ##    ##  ##   ## #            # #
# ##     ##  ##   ## ##   ## ##      #    ## ##   ## ##    ##  ##   ## #      #     # #
# ###    #   ### ### ###  #  ##      ##   #  ### ### ###   ##  ##   ## ##   # ##    # #
# # ######    ### ######### ###       ####    ### ##  ### ### ###  ###  ####  ######  #
#                                                                                     #
#######################################################################################

################################################################################
#                                                                              #
#  ####  ###  #   # #####        ###  #   # ####  ##### #   #                  #
# #     #   # #   # #             #   ##  # #   # #      # #                   #
#  ###  ##### #   # ####          #   # # # #   # ####    #                    #
#     # #   #  # #  #             #   #  ## #   # #      # #                   #
# ####  #   #   #   #####        ###  #   # ####  ##### #   #                  #
#                         #####                                                #
#                                                                              #
################################################################################

sub save_index {
    my ($filename, $index) = @_;

    open(FP, ">:encoding(UTF-8)", $filename) or die "Cannot create index file $filename: $!\n";

    print FP "Field,Key,Index\n";

    foreach my $ind (keys(%$index)) {
        my $ix = $index->{$ind};
        foreach my $key (keys(%$ix)) {
            if($ind eq '_bibkey') {
                print FP "$ind,$key,", $ix->{$key}, "\n";
            }
            else {
                foreach my $value (keys(%{$ix->{$key}})) {
                    print FP "$ind,$key,$value\n";
                }
            }
        }
    }

    close(FP);
}

################################################################################
#                                                                              #
# #      ###   ###  #   # #   # ####        ####  ####                         #
# #     #   # #   # #  #  #   # #   #       #   # #   #                        #
# #     #   # #   # ###   #   # ####        #   # ####                         #
# #     #   # #   # #  #  #   # #           #   # #   #                        #
# #####  ###   ###  #   #  ###  #           ####  ####                         #
#                                     #####                                    #
#                                                                              #
# Find an array of papers in the bibtex database, storing cross-references     #
# from index in each to the other                                              #
################################################################################

sub lookup_db {
    my ($input, $db, $index, $db2in, $in2db, $input_name, $n) = @_;

    my @not_found;
    for(my $i = 0; $i <= $#$input; $i++) {
        my $j = ($input_name eq 'corpus' || $input_name eq 'screen')
            ? &lookup($$input[$i], $db, $index)
            : &lookup_id($$input[$i], $db, $index);
        if($j >= 0) {
            if($n > 1) {
                if(!exists($db2in->{$j}) || scalar(@{$db2in->{$j}}) < $n) {
                    push(@{$db2in->{$j}}, $i);
                    $in2db->{$i} = $j;
                }
                else {
                    &logbook("Record $i of $input_name, linked to article $j ",
                        "in the BibTeX database, is being ignored because ",
                        "we already have $n entries");
                }
            }
            else {
                if(exists($db2in->{$j})) {
                    &logbook("Record $i of $input_name, linked to article $j ",
                        "in the BibTeX database, is being ignored because ",
                        "we already have a $input_name entry for $j");
                }
                else {
                    $db2in->{$j} = $i;
                    $in2db->{$i} = $j;
                }
            }
        }
        else {
            push(@not_found, $i);
        }
    }
    return @not_found;
}

################################################################################
#                                                                              #
# #      ###   ###  #   # #   # ####                                           #
# #     #   # #   # #  #  #   # #   #                                          #
# #     #   # #   # ###   #   # ####                                           #
# #     #   # #   # #  #  #   # #                                              #
# #####  ###   ###  #   #  ###  #                                              #
#                                                                              #
# Find a paper in the bibtex database using its index                          #
################################################################################

sub lookup {
    my ($record, $db, $index) = @_;

    my ($doi, $md5, $ignoring_which_db, $title, $abstract) = @$record;

    my %lk = (
        'doi' => $doi,
        '__md5' => $md5,
        'title' => &TextTK::alns($title),
        'abstract' => md5_hex(&TextTK::alns($abstract))
    );

    my %db_ix;
    foreach my $lk_ix (keys(%lk)) {
        my $lk_val = $lk{$lk_ix};
        if(exists($index->{$lk_ix}->{$lk_val})) {
            $lookup_wins{$lk_ix}++;
            my $db_ixes = $index->{$lk_ix}->{$lk_val};
            foreach my $ix (keys(%{$db_ixes})) {
                $db_ix{$ix}->{$lk_ix}++;
            }
        }
        else {
            $lookup_loss{$lk_ix}++;
        }
    }
    my @opt_ix = keys(%db_ix);
    if(scalar(@opt_ix) == 0) {
        return -1;
    }
    elsif(scalar(@opt_ix) == 1) {
        return $opt_ix[0];
    }
    else {
        my %doi_ix;
        my %other_ix;
        for(my $i = 0; $i <= $#opt_ix; $i++) {
            my $ix = $opt_ix[$i];
            foreach my $key (keys(%{$db_ix{$ix}})) {
                my $n = $db_ix{$ix}->{$key};
                if($key eq 'doi') {
                    $doi_ix{$ix} += $n;
                }
                else {
                    $other_ix{$ix} += $n;
                }
            }
        }
        my @doi_ixes = keys(%doi_ix);
        my @other_ixes = keys(%other_ix);
        if(scalar(@other_ixes) == 1) {
            if(!exists($doi_ix{$other_ixes[0]})) {
                &logbook("DOI $doi is not matched with title \"$title\" in BibTeX");
                my $paper = $db->[$index->{'doi'}->{$doi}];
                if(exists($paper->{'title'})) {
                    &logbook("\tBibTeX title is \"", $paper->{'title'}, "\"");
                }
            }
            return $other_ixes[0];
        }
        elsif(scalar(@other_ixes) > 1) {
            # This could happen if the title is duplicated but the abstract
            # is not, for example, so it should be safe to return the majority
            # match
            my $ix = shift(@other_ixes);
            my $n_ix = $other_ix{$ix};
            $n_ix += $doi_ix{$ix} if(exists($doi_ix{$ix}));
            foreach my $alt_ix (@other_ixes) {
                my $alt_n_ix = $other_ix{$alt_ix};
                $alt_n_ix += $doi_ix{$alt_ix} if(exists($doi_ix{$alt_ix}));
                if($alt_n_ix > $n_ix) {
                    $ix = $alt_ix;
                    $n_ix = $alt_n_ix;
                }
            }
            return $ix;
        }
        elsif(scalar(@doi_ixes) == 1) {
            # Actually, this would be an odd case. We have a DOI match, but
            # no MD5, title or abstract match. Worth logging in any case.
            &logbook("No corroboration with title (\"$title\"), abstract, ",
                "or MD5 (\"$md5\") for DOI \"$doi\" linked to index ",
                $doi_ixes[0]);
            return $doi_ixes[0];
        }
        else {
            # If we get here then scalar(@doi_ixes) must be > 1 and we
            # cannot uniquely identify the article
            &logbook("Non-unique references returned for DOI \"$doi\": ",
                join(", ", @doi_ixes));
            my $n_diff = &cmp_attr($db, 1, @doi_ixes);
            if($n_diff == 0) {
                &logbook("No differences in fields detected across these references");
                return $doi_ixes[0];
            }
            return -1;
        }
    }
}

################################################################################
#                                                                              #
# #      ###   ###  #   # #   # ####         ###  ####                         #
# #     #   # #   # #  #  #   # #   #         #   #   #                        #
# #     #   # #   # ###   #   # ####          #   #   #                        #
# #     #   # #   # #  #  #   # #             #   #   #                        #
# #####  ###   ###  #   #  ###  #            ###  ####                         #
#                                     #####                                    #
#                                                                              #
################################################################################

sub lookup_id {
    my ($record, $db, $index) = @_;
    
    my ($doi, $md5) = @$record;

    my %lk;
    $lk{'doi'} = $doi if($doi =~ /\//);
    $lk{'__md5'} = $md5 if($md5 =~ /^[0-9a-f]+$/);

    my %db_ix;
    foreach my $lk_ix (keys(%lk)) {
        my $lk_val = $lk{$lk_ix};
        if(exists($index->{$lk_ix}->{$lk_val})) {
            $lookup_wins{$lk_ix}++;
            my $db_ixes = $index->{$lk_ix}->{$lk_val};
            foreach my $ix (keys(%$db_ixes)) {
                $db_ix{$ix}++;
            }
        }
        else {
            $lookup_loss{$lk_ix}++;
        }
    }
    my @opt_ix = keys(%db_ix);
    if(scalar(@opt_ix) == 0) {
        return -1;
    }
    elsif(scalar(@opt_ix) == 1) {
        return $opt_ix[0];
    }
    else {
        &logbook("Non-unique references returned for DOI \"$doi\" and/or MD5 \"$md5\": ",
            join(", ", @opt_ix));
        my $n_diff = &cmp_attr($db, 1, @opt_ix);
        if($n_diff == 0) {
            &logbook("No differences detected between these non-unique references");
            return $opt_ix[0];
        }
        return -1 * scalar(@opt_ix);
    }
}

################################################################################
#                                                                              #
# #      ###   ###  #   # #   # ####        ####   ###  ####                   #
# #     #   # #   # #  #  #   # #   #       #   #   #   #   #                  #
# #     #   # #   # ###   #   # ####        ####    #   ####                   #
# #     #   # #   # #  #  #   # #           #   #   #   #   #                  #
# #####  ###   ###  #   #  ###  #           ####   ###  ####                   #
#                                     #####                                    #
#                                                                              #
################################################################################

sub lookup_bib {
    my ($db, $bib, $source, $year, $surname, $volume, $issue, $pages) = @_;

    my @results;

    $source = uc($source);
    $surname = lc(&Latin::no_accents($surname));
    if(exists($bib->{$source}->{$year}->{$surname})) {
        my $ixes = $bib->{$source}->{$year}->{$surname};
        IX: foreach my $ix (@$ixes) {
            my $paper = $db->[$ix];
            if(defined($volume)) {
                if(exists($paper->{'volume'}) && $volume ne $paper->{'volume'}) {
                    next IX;
                }
                if(defined($issue)) {
                    if(exists($paper->{'number'}) && $paper->{'number'} ne $issue) {
                        next IX;
                    }
                    if(defined($pages)) {
                        if(exists($paper->{'pages'})) {
                            my @p1 = split(/\D/, $pages);
                            my @p2 = split(/\D/, $paper->{'pages'});
                            next IX if $p1[0] != $p2[0];
                        }
                    }
                }
            }
            push(@results, $ix);
        }
    }

    return @results;
}

################################################################################
#                                                                              #
# #      ###   ###  #   # #   # ####                                           #
# #     #   # #   # #  #  #   # #   #                                          #
# #     #   # #   # ###   #   # ####                                           #
# #     #   # #   # #  #  #   # #                                              #
# #####  ###   ###  #   #  ###  #                                              #
#                                     #####                                    #
#                                                                              #
#  ####  #### ####  ##### ##### #   #                                          #
# #     #     #   # #     #     ##  #                                          #
#  ###  #     ####  ####  ####  # # #                                          #
#     # #     #   # #     #     #  ##                                          #
# ####   #### #   # ##### ##### #   #                                          #
#                                                                              #
################################################################################

sub lookup_screen {
    my ($lookup, $lkup_txt, $index, $scr2db, $lkup2db, $db2lkup, @lost) = @_;

    my @lost_lost;
    foreach my $ix (@lost) {
        my $results = $$lookup[$ix];
        my $md5 = $$results[$R_MD5];
        my $doi = $$results[$R_DOI];

        if(exists($index->{$doi}) && exists($index->{$md5})) {
            if($index->{$doi} != $index->{$md5}) {
                &logbook("Paper ", ($ix + 1), " in $lkup_txt, ",
                    " DOI $doi, MD5 $md5 points to ",
                    "two different indexes in screening data (",
                    $index->{$doi}, " and ", $index->{$md5}, ")");
            }
            else {
                my $db_ix = $scr2db->{$index->{$doi}};
                $db2lkup->{$db_ix} = $ix;
                $lkup2db->{$ix} = $db_ix;
            }
        }
        elsif(exists($index->{$doi})) {
            my $db_ix = $scr2db->{$index->{$doi}};
            $db2lkup->{$db_ix} = $ix;
            $lkup2db->{$ix} = $db_ix;
        }
        elsif(exists($index->{$md5})) {
            my $db_ix = $scr2db->{$index->{$md5}};
            $db2lkup->{$db_ix} = $ix;
            $lkup2db->{$ix} = $db_ix;
        }
        else {
            push(@lost_lost, $ix);
        }
    }

    return @lost_lost;
}

################################################################################
#                                                                              #
# #   #  ###  #####  #### #   #                                                #
# ## ## #   #   #   #     #   #                                                #
# # # # #####   #   #     #####                                                #
# #   # #   #   #   #     #   #                                                #
# #   # #   #   #    #### #   #                                                #
#                               #####                                          #
#                                                                              #
# ####  ##### #   #  ###  ##### #   #  ####                                    #
# #   # #     #   #   #   #     #   # #                                        #
# ####  ####  #   #   #   ####  # # #  ###                                     #
# #   # #      # #    #   #     # # #     #                                    #
# #   # #####   #    ###  #####  # #  ####                                     #
#                                                                              #
# In DIRE need of code tidy                                                    #
################################################################################

sub match_reviews {
    my ($as, $rv, $rv2as, $as2db, $db) = @_;

    my %author_misspellings = (
        'MEHDI SAQALLI' => 'SAQALLI',
        'BOGADO TOMASIELLO' => 'TOMASIELLO',
        'JUBERT' => 'JOUBERT',
        'SRBLIJNOVIC' => 'SRBLJINOVIC',
        'GURRAMM' => 'GURRAM',
        'MARTINS MONTEIRO' => 'MONTEIRO',
        'SMAGJL' => 'SMAJGL',
        'VIEGAS DE LIMA' => 'DE LIMA',
        'HASE' => 'HAASE',
        'ATTI' => 'DEGLI ATTI',
        'CIOFI DEGLI ATTI' => 'DEGLI ATTI',
        'COCUCCI' => 'JAVIER COCUCCI',
        'DAMAREST' => 'DEMAREST',
        'BEDHAM' => 'BADHAM',
        'ORDONEZ MEDINA' => 'MEDINA',
        'ORDONEZ' => 'MEDINA',
        'NOLDEKE' => 'NOELDEKE',
        'MANH VU' => 'VU',
        'AMINEH' => 'GHORBANI',
        'IONESCO' => 'IONESCU',
    );
    my %journal_specific_author_misspellings = (
        'SANTOS' => { 'PLOS ONE' => 'IGNACIO SANTOS',
            'JOURNAL OF ARTIFICIAL SOCIETIES AND SOCIAL SIMULATION' => 'DOS SANTOS' }
    );
    my %brute_force = (
        123 => [67, 'Richard', 'Feitosa', 2011, 'Computers, Environment and Urban Systems'],
        124 => [215, 'Richard', 'Yang', 2019, 'Computers, Environment and Urban Systems'],
        184 => [190, 'Doug', 'Shi', 2020, 'PLoS ONE'],
        185 => [15, 'Doug', 'Shi', 2020, 'PLoS ONE'],
        186 => [24, 'Doug', 'Keskinocak', 2020, 'PLoS ONE'],
        72 => [212, 'Alison', 'Alisoltani', 2020, 'Smart Innovation, Systems and Technologies']
    );
    my %ignore = (
        59 => [159, 'Gary', 'Mintram', 2022, 'PLoS ONE'],
    );

    my %assignments;
    my @papers;
    my %jnau;
    my %all_authors;
    for(my $i = 0; $i <= $#$as; $i++) {
        my $adoi = $as->[$i]->[$A_DOI];
        my $amd5 = $as->[$i]->[$A_MD5];

        my $r1 = $as->[$i]->[$A_R1];
        my $r2 = $as->[$i]->[$A_R2];

        if(exists($as2db->{$i})) {
            $papers[$i] = $db->[$as2db->{$i}];
            
            push(@{$assignments{$r1}}, $i);
            push(@{$assignments{$r2}}, $i);

            my $jn = $papers[$i]->{'__source'};
            foreach my $au (&BibTeX::author_surnames($papers[$i])) {
                my $au_key = uc(&Latin::no_accents($au));
                if(exists($author_misspellings{$au_key})) {
                    &logbook("Author $au_key will mask correction to ",
                        $author_misspellings{$au_key});
                }
                if(exists($journal_specific_author_misspellings{$au_key})) {
                    if(exists($journal_specific_author_misspellings{$au_key}->{uc($jn)})) {
                        &logbook("Author $au_key will mask correction to ",
                            $journal_specific_author_misspellings{$au_key}->{uc($jn)},
                            " in $jn");
                    }
                }
                $jnau{uc($jn)}->{$au_key}->{$i}++;
                $all_authors{$au_key}->{$i}++;
            }
        }
        else {
            &logbook("No database index found for assignment $i to $r1 and $r1 ",
                "(DOI: $adoi / MD5: $amd5)");
        }
    }

    my $n_reviews = 0;
    my $n_ok = 0;
    my $n_one_error = 0;
    my $n_nothing = 0;
    my $n_not_nothing = 0;
    my $n_multiple = 0;
    my $n_author = 0;
    my $n_brute_force = 0;
    my $n_ignored = 0;
    my %n_which_wrong;

    for(my $j = 0; $j <= $#$rv; $j++) {
        $n_reviews++;

        my $r = $$rv[$j];

        my ($who, $au, $yr, $jn, $vl, $is, $ppstr)
             = ($$r[$GWHO], $$r[$GAUTH], $$r[$GYEAR], $$r[$GJOURN],
                $$r[$GVOL], $$r[$GISS], $$r[$GPAGES]);

        $au =~ s/^\s+//;
        $au =~ s/\s+$//;
        $au =~ s/[,;]$//;
        $au = uc(&Latin::no_accents($au));
        if(!exists($all_authors{$au}) && exists($author_misspellings{$au})) {
            $au = $author_misspellings{$au};
        }
        if(!exists($jnau{uc($jn)}->{$au}) && exists($journal_specific_author_misspellings{$au}->{uc($jn)})) {
            $au = $journal_specific_author_misspellings{$au}->{uc($jn)};
        }
        $yr =~ s/\D//g;
        $vl =~ s/\D//g;
        $vl = "[NA]" if(length($vl) == 0);
        $is =~ s/\D//g;
        $is = "[NA]" if(length($is) == 0);
        $ppstr =~ s/^\s+//;
        $ppstr =~ s/\s+$//;
        my @pp = split(/\D+/, $ppstr);
        if(length($ppstr) == 0) {
            @pp = ();
            $ppstr = "[NA]";
        }
        else {
            $ppstr = join("--", @pp);
        }

        if(exists($brute_force{$j}) || exists($ignore{$j})) {
            die "BUG!!" if(exists($brute_force{$j}) && exists($ignore{$j}));

            my $data = exists($brute_force{$j}) ? $brute_force{$j} : $ignore{$j};
            my $desc = exists($brute_force{$j}) ? 'Bruce force' : 'Ignored';

            my ($i, $assignee, $author, $year, $journal) = @$data;

            if($who ne $assignee) {
                die "$desc assignment $j->$i has assignee mismatch ($who ne $assignee)\n";
            }

            my $paper = $papers[$i];
            my $yy = $paper->{'year'};
            my $sn = (&BibTeX::author_surnames($paper))[0];
            my $so = $paper->{'__source'};

            if(uc($sn) ne uc($author)) {
                die "$desc assignment $j->$i has author mismatch ($sn ne $author)\n";
            }
            if($year != $yy) {
                die "$desc assignment $j->$i has year mismatch ($yy != $year)\n";
            }
            if(uc($so) ne uc($journal)) {
                die "$desc assignment $j->$i has journal mismatch ($so ne $journal)\n";
            }

            if(exists($brute_force{$j})) {
                $rv2as->{$j} = $i;
                $n_brute_force++;
            }
            else {
                $n_ignored++;
            }
            next;   
        }

        if(exists($assignments{$who})) {
            my @candidates;
            my @one_wrongs;
            my %which_wrongs;

            foreach my $i (@{$assignments{$who}}) {
                my $k = $as2db->{$i};
                my $paper = $papers[$i];
                my $n_wrong = 0;

                my $djn = $paper->{'__source'};
                if(uc($djn) ne uc($jn)) {
                    $n_wrong++;
                    $which_wrongs{$i}->{'__source'}++;
                }

                my $dyr = $paper->{'year'};
                if($dyr != $yr) {
                    $n_wrong++;
                    $which_wrongs{$i}->{'year'}++;
                }

                my @dau = &BibTeX::author_surnames($paper);
                if(!grep { uc(&Latin::no_accents($_)) eq $au } @dau) {
                    $n_wrong++;
                    $which_wrongs{$i}->{'author'}++;
                }

                my @details = ($i, $k, uc(&Latin::no_accents($dau[0])), $dyr);

                if(exists($paper->{'volume'})) {
                    my $dvl = $paper->{'volume'};
                    $dvl =~ s/\D//g;
                    if(length($dvl) > 0 && $vl ne "[NA]" && $dvl != $vl) {
                        $n_wrong++;
                        $which_wrongs{$i}->{'volume'}++;
                    }
                    push(@details, $dvl);
                }
                else {
                    push(@details, "[NA]");
                }

                if(exists($paper->{'number'})) {
                    my $dis = $paper->{'number'};
                    $dis =~ s/\D//g;
                    if(length($dis) > 0 && $is ne "[NA]" && $dis != $is) {
                        $n_wrong++;
                        $which_wrongs{$i}->{'number'}++;
                    }
                    push(@details, $dis);
                }
                else {
                    push(@details, "[NA]");
                }

                if(exists($paper->{'__pages'})) {
                    my $dppstr = $paper->{'__pages'};
                    if(length($dppstr) > 0 && $ppstr ne "[NA]" && $ppstr ne $dppstr) {
                        $n_wrong++;
                        $which_wrongs{$i}->{'__pages'}++;
                    }
                    push(@details, $dppstr);
                }
                else {
                    push(@details, "[NA]");
                }

                if($n_wrong == 0) {
                    push(@candidates, [ @details ]);
                }
                elsif($n_wrong == 1) {
                    push(@one_wrongs, [ @details ]);
                }
            }

            if(scalar(@candidates) == 0) {
                &logbook("No candidate found for review $j by $who of $au ($yr) $jn $vl ($is), $ppstr");
                if(scalar(@one_wrongs) == 0) {
                    &logbook("No candidate with one error either");
                    $n_nothing++;
                    my @aus = keys(%{$jnau{uc($jn)}});
                    if(grep { uc(&Latin::no_accents($_)) eq $au } @aus) {
                        my $n = 0;
                        my $ix = -1;
                        foreach my $i (keys(%{$jnau{uc($jn)}->{$au}})) {
                            my $paper = $papers[$i];
                            my $year = $paper->{'year'};
                            my $sn = (&BibTeX::author_surnames($paper))[0];
                            my $volume = exists($paper->{'volume'}) ? $paper->{'volume'} : "[NA]";
                            my $number = exists($paper->{'number'}) ? $paper->{'number'} : "[NA]";
                            my $pages = exists($paper->{'__pages'}) ? $paper->{'__pages'} : "[NA]";
                            &logbook("\tFound [$i] $sn ($year) $jn $volume ($number), $pages assigned to ",
                                $as->[$i]->[$A_R1], " and ", $as->[$i]->[$A_R2]);
                            $n++;
                            $ix = $i;
                        }
                        if($n == 1) {
                            my $n_au = scalar(keys(%{$all_authors{$au}}));
                            &logbook("Using the above single option -- there are $n_au ",
                                "papers by $au in the assignments");
                            $rv2as->{$j} = $ix;
                            $n_not_nothing++;
                        }
                    }
                    else {
                        &logbook("Nothing with author $au in $jn in any assignment");
                        my $n_anywhere = 0;
                        my $n_possibly_anywhere = 0;
                        if(exists($all_authors{$au})) {
                            my $n = 0;
                            my $ix = -1;
                            foreach my $i (keys(%{$all_authors{$au}})) {
                                my $paper = $papers[$i];
                                my $year = $paper->{'year'};
                                my $sn = (&BibTeX::author_surnames($paper))[0];
                                my $journal = $paper->{'__source'};
                                my $volume = exists($paper->{'volume'}) ? $paper->{'volume'} : "[NA]";
                                my $number = exists($paper->{'number'}) ? $paper->{'number'} : "[NA]";
                                my $pages = exists($paper->{'__pages'}) ? $paper->{'__pages'} : "[NA]";
                                &logbook("\tFound [$i] $sn ($year) $journal $volume ($number), $pages assigned to ",
                                    $as->[$i]->[$A_R1], " and ", $as->[$i]->[$A_R2]);
                                $n_anywhere++;
                                $n++;
                                $ix = $i;
                            }
                            if($n == 1) {
                                my $n_au = scalar(keys(%{$all_authors{$au}}));
                                &logbook("Using the above single option -- there are $n_au ",
                                    "papers by $au in the assignments");
                                $rv2as->{$j} = $ix;
                                $n_not_nothing++;
                                $n_which_wrong{'__source'}++;
                            }
                        }
                        else {
                            my $au_sperr = -1;
                            my @au_i = ();
                            foreach my $all (keys(%all_authors)) {
                                my $sperr = (length($all) - &TextTK::match_len($all, $au)) / length($all);
                                if($#au_i == -1 || $sperr == $au_sperr) {
                                    foreach my $i (keys(%{$all_authors{$all}})) {
                                        push(@au_i, $i);
                                    }
                                    $au_sperr = $sperr;
                                }
                                elsif($sperr < $au_sperr) {
                                    @au_i = ();
                                    foreach my $i (keys(%{$all_authors{$all}})) {
                                        push(@au_i, $i);
                                    }
                                }
                            }
                            foreach my $i (@au_i) {
                                my $paper = $papers[$i];
                                my $year = $paper->{'year'};
                                my $journal = $paper->{'__source'};
                                my $sn = (&BibTeX::author_surnames($paper))[0];
                                my $volume = exists($paper->{'volume'}) ? $paper->{'volume'} : "[NA]";
                                my $number = exists($paper->{'number'}) ? $paper->{'number'} : "[NA]";
                                my $pages = exists($paper->{'__pages'}) ? $paper->{'__pages'} : "[NA]";
                                &logbook("\tFound [$i] $sn ($year) $journal $volume ($number), $pages assigned to ",
                                    $as->[$i]->[$A_R1], " and ", $as->[$i]->[$A_R2]);
                                $n_possibly_anywhere++;
                            }
                        }
                        if($n_anywhere == 0) {
                            if($n_possibly_anywhere == 0) {
                                &logbook("Nothing with anything like author $au in any journal!");
                            }
                            else {
                                &logbook("Nothing with author $au in any journal, but ",
                                    "$n_possibly_anywhere with some spelling errors found");
                            }
                        }
                    }
                }
                else {
                    &logbook("One or more candidates with one error:");
                    my $au_sperr = -1;
                    my $au_i = -1;
                    foreach my $one_wrong (@one_wrongs) {
                        my ($i, $k, $dau, $dyr, $dvl, $dis, $dpp) = @$one_wrong;
                        my $source = $papers[$i]->{'__source'};
                        &logbook("\t[$i|$k] $dau ($dyr) $source $dvl ($dis), $dpp");

                        if($au eq $dau) {
                            $au_i = $i;
                            $au_sperr = 0;
                        }
                        else {
                            my $sperr = (length($dau) - &TextTK::match_len($au, $dau)) / length($dau);
                            if($au_i == -1 || $sperr < $au_sperr) {
                                $au_i = $i;
                                $au_sperr = $sperr;
                            }
                        }
                    }
                    if(scalar(@one_wrongs) == 1) {
                        $rv2as->{$j} = $one_wrongs[0]->[0];
                        my $which_ones = $which_wrongs{$one_wrongs[0]->[0]};
                        my @which_keys = keys(%$which_ones);
                        die "BUG: too many wrongs (", join(", ", @which_keys), ")\n"
                            if(scalar(@which_keys) > 1);
                        
                        &logbook("Using the above single option with one error in $which_keys[0]");
                        
                        $n_which_wrong{$which_keys[0]}++;
                        $n_one_error++;
                    }
                    elsif($au_i >= 0) {
                        $rv2as->{$j} = $au_i;
                        &logbook("Using option $au_i with the closest author match");
                        $n_author++;
                    }
                } 
            }
            elsif(scalar(@candidates) == 1) {
                $rv2as->{$j} = $candidates[0]->[0];
                $n_ok++;
            }
            else {
                &logbook("Multiple candidates for review $j by $who of $au ($yr) $jn $vl ($is), $ppstr");

                foreach my $candidate (@candidates) {
                    my ($i, $k, $au, $yr, $dvl, $dis, $dpp) = @$candidate;
                    &logbook("\t[$i|$k] $au ($yr) $jn $dvl ($dis), $dpp");
                }
                $n_multiple++;
            }
        }
        else {
            &logbook("No assignments found for reviewer $who");
        }
    }

    &logbook("#", ("#" x 70));
    &logbook("Review report summary:\n  + Number of reviews: $n_reviews");
    &logbook("  + Number of reviews matched by brute force: $n_brute_force");
    &logbook("  + Number of reviews ignored: $n_ignored");
    &logbook("  + Number of reviews matched OK: $n_ok");
    &logbook("  + Number of reviews matched with one error: $n_one_error");
    foreach my $field (sort {$a cmp $b} keys(%n_which_wrong)) {
        &logbook("    + $field: ", $n_which_wrong{$field});
    }
    &logbook("  + Number of reviews matched by choosing closest author: $n_author");
    &logbook("  + Number of reviews with multiple exactly matching candidates: $n_multiple");
    &logbook("  + Number of reviews with no matching candidates: $n_nothing");
    &logbook("    + Of which $n_not_nothing could be assigned after analysis");
    &logbook("#", ("#" x 70));

    # Later reviews by the same person of the same paper supercede earlier ones
    my %re_reviews;         # {person}->{assignment $i}->review $j

    foreach my $j (keys(%$rv2as)) {
        if(exists($re_reviews{$rv->[$j]->[$GWHO]}->{$rv2as->{$j}})) {
            delete $rv2as->{$re_reviews{$rv->[$j]->[$GWHO]}->{$rv2as->{$j}}};
        }
        $re_reviews{$rv->[$j]->[$GWHO]}->{$rv2as->{$j}} = $j;
    }

    # Create a hash for all the assignment papers $i found
    my %found_assignments;
    foreach my $who (keys(%re_reviews)) {
        foreach my $i (keys(%{$re_reviews{$who}})) {
            push(@{$found_assignments{$i}}, $who);
        }
    }
    my $n_issues = 0;
    my %reassignments;      # {$i}->{$orig}->$who
    for(my $i = 0; $i <= $#$as; $i++) {
        $found_assignments{$i} = [] if(!exists($found_assignments{$i}));
        my $n = scalar(@{$found_assignments{$i}});

        if($n == 2) {
            my ($who1, $who2) = @{$found_assignments{$i}};

            if($who1 eq $as->[$i]->[$A_R1]) {
                $as->[$i]->[$A_RV1] = $re_reviews{$who1}->{$i};
            }
            elsif($who1 eq $as->[$i]->[$A_R2]) {
                $as->[$i]->[$A_RV2] = $re_reviews{$who1}->{$i};
            }
            elsif($who2 eq $as->[$i]->[$A_R2]) {
                $as->[$i]->[$A_RV1] = $re_reviews{$who1}->{$i};
                $reassignments{$i}->{$as->[$i]->[$A_R1]} = $who1;
            }
            else {
                $as->[$i]->[$A_RV2] = $re_reviews{$who1}->{$i};
                $reassignments{$i}->{$as->[$i]->[$A_R2]} = $who1;
            }

            if($who2 eq $as->[$i]->[$A_R2]) {
                $as->[$i]->[$A_RV2] = $re_reviews{$who2}->{$i};
            }
            elsif($who2 eq $as->[$i]->[$A_R1]) {
                $as->[$i]->[$A_RV1] = $re_reviews{$who2}->{$i};
            }
            elsif($who1 eq $as->[$i]->[$A_R1]) {
                $as->[$i]->[$A_RV2] = $re_reviews{$who2}->{$i};
                $reassignments{$i}->{$as->[$i]->[$A_R2]} = $who2;
            }
            else {
                $as->[$i]->[$A_RV1] = $re_reviews{$who2}->{$i};
                $reassignments{$i}->{$as->[$i]->[$A_R1]} = $who1;
            }
            next;
        }
        $n_issues++;
        my $paper = $papers[$i];
        my $year = $paper->{'year'};
        my $journal = $paper->{'__source'};
        $journal = $shortj{$journal} if(exists($shortj{$journal}));
        my $sn = (&BibTeX::author_surnames($paper))[0];
        my $volume = exists($paper->{'volume'}) ? $paper->{'volume'} : "[NA]";
        my $number = exists($paper->{'number'}) ? $paper->{'number'} : "[NA]";
        my $pages = exists($paper->{'__pages'}) ? $paper->{'__pages'} : "[NA]";
        &logbook("[$i] $sn ($year) $journal $volume ($number), $pages assigned to ",
            $as->[$i]->[$A_R1], " and ", $as->[$i]->[$A_R2], " has $n reviews by ",
            join(", ", @{$found_assignments{$i}}));
    }
    &logbook("All assigned papers have exactly two reviews") if($n_issues == 0);
    if(scalar(keys(%reassignments)) > 0) {
        &logbook("N.B.");
        foreach my $i (sort {$a <=> $b} keys(%reassignments)) {
            foreach my $orig (sort {$a cmp $b} keys(%{$reassignments{$i}})) {
                &logbook("\t[$i] assigned to $orig was done by ",
                    $reassignments{$i}->{$orig});
            }
        }
    }
    &logbook("#", ("#" x 70));
}

################################################################################
#                                                                              #
# #   # ##### ####   #### #####                                                #
# ## ## #     #   # #     #                                                    #
# # # # ####  ####  #  ## ####                                                 #
# #   # #     #   # #   # #                                                    #
# #   # ##### #   #  #### #####                                                #
#                               #####                                          #
#                                                                              #
# ####  ##### #   #  ###  ##### #   #  ####                                    #
# #   # #     #   #   #   #     #   # #                                        #
# ####  ####  #   #   #   ####  # # #  ###                                     #
# #   # #      # #    #   #     # # #     #                                    #
# #   # #####   #    ###  #####  # #  ####                                     #
#                                                                              #
################################################################################

sub merge_reviews {
    my ($as, $rv, $as2db, $db2mrg, $mrg2db) = @_;

    my @merged;
    for(my $i = 0; $i <= $#$as; $i++) {
        my @assignment = @{$$as[$i]};

        if($#assignment == $A_RV2) {
            my $j1 = $assignment[$A_RV1];
            my $j2 = $assignment[$A_RV2];
            my ($in, @merge) = &merge_review($$rv[$j1], $$rv[$j2]);
            if($in) {
                push(@merged, [ @merge ]);
                my $dbix = $as2db->{$i};
                $db2mrg->{$dbix} = $#merged;
                $mrg2db->{$#merged} = $dbix;
            }
        }
        else {
            &logbook("Assignment $i does not have exactly two reviews -- not merging");
        }
    }
    &logbook("From ", scalar(@$as), " assignments, ", scalar(@merged),
        " merged reviews have been created");
    return @merged;
}

################################################################################
#                                                                              #
#  ###   ###    #    ###   ###                                                 #
# #   # #   #  ##   #   # #   #                                                #
# ##### # # #   #     ##    ##                                                 #
# #   # #  ##   #    #    #   #                                                #
# #   #  ####  ###  #####  ###                                                 #
#                                                                              #
################################################################################

sub aq123 {
    my ($assignment, $rv) = @_;

    my @qun = ($GISABM, $GISSOC, $GISEMP);
    my @ans = ("NA", "NA", "NA");
    if($#$assignment == $A_RV2) {
        my $j1 = $$assignment[$A_RV1];
        my $j2 = $$assignment[$A_RV2];
        die "$j1 in assignment [", join(", ", @$assignment), "] is out of range\n"
            if($j1 < 0 || $j1 > $#$rv);
        die "$j2 in assignment [", join(", ", @$assignment), "] is out of range\n"
            if($j2 < 0 || $j2 > $#$rv);
        my $r1 = $$rv[$j1];
        my $r2 = $$rv[$j2];
        for(my $i = 0; $i <= $#qun; $i++) {
            my $a1 = $$r1[$qun[$i]];
            my $a2 = $$r2[$qun[$i]];
            if($a1 eq "Yes") {
                if($a2 eq "Yes" || $a2 eq "I cannot be sure from reading the paper" || $a2 eq "NA") {
                    $ans[$i] = "Yes";
                }
                else {
                    $ans[$i] = "Disputed";
                }
            }
            elsif($a1 eq "No") {
                if($a2 ne "Yes") {
                    $ans[$i] = "No";
                }
                else {
                    $ans[$i] = "Disputed";
                }
            }
            elsif($a2 eq "Yes") {
                if($a1 eq "I cannot be sure from reading the paper" || $a1 eq "NA") {
                    $ans[$i] = "Yes";
                }
                else {
                    $ans[$i] = "Disputed";
                }
            }
            elsif($a2 eq "No") {
                $ans[$i] = "No";
            }
            elsif($a1 eq $a2 && $a1 eq "I cannot be sure from reading the paper") {
                $ans[$i] = "Unsure";
            }
            elsif($a1 eq $a2 && $a1 eq "NA") {
                $ans[$i] = "NA";
            }
            else {
                $ans[$i] = "No";
            }
        }
    }
    return @ans;
}

################################################################################
#                                                                              #
#  ###   ####       ##### #      ###   ####  ###  ####  #     #####            #
#   #   #           #     #       #   #       #   #   # #     #                #
#   #    ###        ####  #       #   #  ##   #   ####  #     ####             #
#   #       #       #     #       #   #   #   #   #   # #     #                #
#  ###  ####        ##### #####  ###   ####  ###  ####  ##### #####            #
#             #####                                                            #
#                                                                              #
################################################################################

sub is_eligible {
    my ($r1, $r2) = @_;

    my @gform_eligible = ($GISABM, $GISSOC, $GISEMP);

    my @answers = ($$r1[$GISABM], $$r1[$GISSOC], $$r1[$GISEMP]);

    # Eligibility. If one person says it is ineligible, then it is ineligible.
    # If one person is unsure, take the other's answer

    my $is_eligible = ($$r1[$GISSPINF] !~ /^N\/A/ && $$r2[$GISSPINF] !~ /^N\/A/);
    for(my $j = 0; $j <= $#gform_eligible; $j++) {
        my $i = $gform_eligible[$j];

        # Regrettably the 'empirical' question $GISEMP was not required
        if($answers[$j] eq "NA" && $$r2[$i] ne "NA") {
            $answers[$j] = $$r2[$i];
        }

        # Handle the "I cannot be sure" cases
        if($answers[$j] eq "I cannot be sure from reading the paper"
            && $answers[$j] ne $$r2[$i] && $$r2[$i] ne "NA")
        {
            $answers[$j] = $$r2[$i];
        }

        if($answers[$j] ne "Yes") {
            $is_eligible = 0;
        }
    }

    return ($is_eligible, $answers[0], $answers[1], $answers[2]);
}

################################################################################
#                                                                              #
# #   # ##### ####   #### #####       ####  ##### #   #  ###  ##### #   #      #
# ## ## #     #   # #     #           #   # #     #   #   #   #     #   #      #
# # # # ####  ####  #  ## ####        ####  ####  #   #   #   ####  # # #      #
# #   # #     #   # #   # #           #   # #      # #    #   #     # # #      #
# #   # ##### #   #  #### #####       #   # #####   #    ###  #####  # #       #
#                               #####                                          #
#                                                                              #
################################################################################

sub merge_review {
    my ($r1, $r2) = @_;

    my @gform_paper = ($GAUTH, $GYEAR, $GJOURN, $GVOL, $GISS, $GPAGES);
    my @gform_data = ($GISSPINF, $GSPEXT, $GSPNAM, $GSPTY, $GISSPN, $GSPRAS, $GSPVEC,
        $GNSTEP, $GSTEPTY, $GSOCTY, $GNAGENT, $GAGTY, $GNAGRW, $GNRUN, $GISCOMPINF,
        $GCOMPTY, $GISCOMPLIM, $GLIMPHR, $GLIMTY, $GISINT);
    my @gform_numeric = ($GSPRAS, $GSPVEC, $GNSTEP, $GNAGENT, $GNAGRW, $GNRUN);
    my @gform_boolean_data = ($GISSPINF, $GISSPN, $GISCOMPINF, $GISCOMPLIM, $GISINT);
    my @gform_radio_data = ($GSPEXT, $GSPTY, $GSTEPTY, $GAGTY, $GCOMPTY);
    my @gform_checkbox = ($GSOCTY, $GLIMPHR, $GLIMTY);
    my @gform_text = ($GSPNAM);

    my @merge = @$r1;

    my ($is_eligible, $is_abm, $is_soc, $is_emp) = &is_eligible($r1, $r2);
    $merge[$GISABM] = $is_abm;
    $merge[$GISSOC] = $is_soc;
    $merge[$GISEMP] = $is_emp;

    # If the paper is ineligible, then everything is "NA"
    if(!$is_eligible) {
        foreach my $i (@gform_data) {
            $merge[$i] = "NA";
        }
        return (0, @merge);
    }

    # If one person says 'NA' then take the other person's entry -- the assumption
    # is that the person who said 'NA' didn't spot data the other person found

    foreach my $i (@gform_data) {
        if($merge[$i] eq "NA" && $$r2[$i] ne "NA") {
            $merge[$i] = $$r2[$i];
        }
        # We don't need to do $merge[$i] ne "NA"
    }

    # For Boolean answers, if one person says 'Maybe' and the other does not,
    # then accept the other person's answer
    foreach my $i (@gform_boolean_data) {
        if($merge[$i] eq "Maybe" && $$r2[$i] ne "Maybe" && $$r2[$i] ne "NA") {
            $merge[$i] = $$r2[$i];
        }
    }

    # For Boolean answers, if the two reviewers give opposite answers (T & F)
    # then the paper will need to be done again ideally. This is recorded as
    # 'Disputed', unless it's $GISINT, when if one person thought it was
    # interesting, then we'll keep that

    foreach my $i (@gform_boolean_data) {
        if($i == $GISINT) {
            # Interesting? 'Truth' table. (Merge In is what $merge[$i] will be
            # at this point in the code given $$r1[$i] and $$r2[$i])
            #
            # R1    R2    | Merge In | Merge Out
            # ------------+----------+----------
            # NA    NA    | NA       | NA
            # NA    No    | No       | No
            # NA    Maybe | Maybe    | Maybe
            # NA    Yes   | Yes      | Yes
            # No    NA    | No       | No
            # No    No    | No       | No
            # No    Maybe | No       | No
            # No    Yes   | No       | Yes
            # Maybe NA    | Maybe    | Maybe
            # Maybe No    | No       | No
            # Maybe Maybe | Maybe    | Maybe
            # Maybe Yes   | Yes      | Yes
            # Yes   NA    | Yes      | Yes
            # Yes   No    | Yes      | Yes
            # Yes   Maybe | Yes      | Yes
            # Yes   Yes   | Yes      | Yes 
            if($$r2[$i] ne "NA" && ($merge[$i] eq "NA" || $merge[$i] eq "No")) {
                $merge[$i] = $$r2[$i];
            }
        }
        elsif($$r2[$i] ne "NA" && $$r2[$i] ne "Maybe" && $merge[$i] ne $$r2[$i]) {
            $merge[$i] = "Disputed";
        }
    }

    # For numeric answers, so long as they are the same order of magnitude,
    # we will take whichever answer has the more significant figures. If they
    # both have the same number of significant figures, we will take the
    # greater of the two answers. If they are not of the same order of
    # magnitude, then it's NA

    foreach my $i (@gform_numeric) {
        if($$r2[$i] ne "NA" && $merge[$i] ne "NA" && $merge[$i] != $$r2[$i]) {
            my $r1str = sprintf("%d", $merge[$i]);
            my $r2str = sprintf("%d", $$r2[$i]);

            if(length($r1str) != length($r2str)) {
                $merge[$i] = "Disputed";
            }
            else {
                $r1str =~ s/0*$//;
                $r2str =~ s/0*$//;

                if(length($r2str) > length($r1str)) {
                    $merge[$i] = $$r2[$i];
                }
                elsif(length($r2str) == length($r1str) && $$r2[$i] > $merge[$i]) {
                    $merge[$i] = $$r2[$i];
                }
                else {
                    # (Nothing; just a reminder that we want to keep $merge[$i])
                }
            }
        }
    }

    # For radio answers, disagreement will have to be NA-ed, with the following
    # exceptions:
    # 
    # 1. $GSPTY -- things are complicated as the answers are not completely
    #               mutually exclusive
    # 2. $GCOMPTY -- we are really only interested in PC or not

    foreach my $i (@gform_radio_data) {
        if($$r2[$i] ne "NA" && $merge[$i] ne $$r2[$i]) {
            if($i == $GCOMPTY) {
                if($merge[$i] ne $$r2[$i] &&
                    ($merge[$i] eq 'Personal computer (desktop/laptop)'
                    || $$r2[$i] eq 'Personal computer (desktop/laptop)'))
                {
                    $merge[$i] = "Disputed";
                    $merge[$GISHPC] = "Maybe";
                }
                else {
                    $merge[$i] .= " / ".$$r2[$i];
                    $merge[$GISHPC] = "Yes";
                }
            }
            elsif($i == $GSPTY) {
                my %ans;

                $ans{'Not a spatially explicit model'} = 0;
                $ans{'Raster (cells, pixels, patches)'} = 0;
                $ans{'Vector (polygons, lines, points)'} = 0;
                $ans{'Mix of Raster and Vector'} = 0;
                # N.B. ('Paper does not say' is treated as NA above,
                # as it could also mean 'Reviewer could not find it')
                $ans{'Other'} = 0;
                $ans{$$r1[$i]}++;
                $ans{$$r2[$i]}++;

                if($ans{'Not a spatially explicit model'} == 1) {
                    # Not a spatially explicit model is incompatible with all
                    # other answers 
                    $merge[$i] = "Disputed";
                }
                elsif($ans{'Mix of Raster and Vector'} == 1 &&
                    $ans{'Raster (cells, pixels, patches)'}
                        + $ans{'Vector (polygons, lines, points)'} == 1) {
                    
                    # Here we assume the other reviewer didn't find the mix
                    $merge[$i] = 'Mix of Raster and Vector';
                }
                elsif($ans{'Other'} == 1) {
                    # Other may be compatible with raster, vector and/or mix
                    # so we generalize to 'Other'
                    $merge[$i] = 'Other';
                }
                else {
                    $merge[$i] = "Disputed";
                }
            }
            else {
                $merge[$i] = "Disputed";
            }
        }
        elsif($i == $GCOMPTY) {
            if($$r2[$i] eq "NA" && $merge[$i] eq "NA") {
                $merge[$GISHPC] = "NA";
            }
            elsif($merge[$i] eq 'Personal computer (desktop/laptop)') {
                $merge[$GISHPC] = "No";
            }
            else {
                $merge[$GISHPC] = "Yes";
            }
        }
    }

    # For checkbox answers we just build a union of the entries, assuming
    # that one reviewer found something the other didn't

    foreach my $i (@gform_checkbox) {
        if($$r2[$i] ne "NA" && $merge[$i] ne $$r2[$i]) {
            my @ans1 = split(/;/, $merge[$i]);
            my @ans2 = split(/;/, $$r2[$i]);

            my %anses;
            foreach my $ans (@ans1, @ans2) {
                $anses{$ans}++;
            }

            $merge[$i] = join(";", keys(%anses));
        }
    }

    # For text answers, we separate the different entries with a /

    foreach my $i (@gform_text) {
        if($$r2[$i] ne "NA" && $merge[$i] ne $$r2[$i]) {
           $merge[$i] .= " / ".$$r2[$i];
        }
    }

    return (1, @merge);
}

################################################################################
#                                                                              #
#  ###  #      ####  ###  ####   ###  ##### #   # #   #  ###                   #
# #   # #     #     #   # #   #   #     #   #   # ## ## #   #                  #
# ##### #     #  ## #   # ####    #     #   ##### # # #   ##                   #
# #   # #     #   # #   # #   #   #     #   #   # #   #  #                     #
# #   # #####  ####  ###  #   #  ###    #   #   # #   # #####                  #
#                                                                              #
# Provides a reimplementation of 'algorithm 2' in bin/GAjournal.pl, which,     #
# after identifying the top N journals (N == 5 in the original study), finds   #
# a set of journals to cover all the Web of Science categories by identifying  #
# the journal with the largest coverage of the remaining uncovered category    #
# having the smallest number of papers. The category coverage is then updated  #
# to include any further categories covered by the selected journal.           #
################################################################################

sub algorithm2 {
    my ($prog, $counts, $src_wos, @journals) = @_;

    my $any_left = 1;
    while($any_left) {
        $any_left = 0;
        my @remnants;
        foreach my $cat (keys(%$prog)) {
            if($$prog{$cat} == 0) {
                $any_left = 1;
                push(@remnants, $cat);
            }
        }
        last if(!$any_left);
        @remnants = sort { $counts->{$a} <=> $counts->{$b} } @remnants;
        my $next_cat = $remnants[0];
        my $next_src;
        my $n_next_src = -1;
        foreach my $src (keys(%$src_wos)) {
            next if(!exists($src_wos->{$src}->{$next_cat}));
            if($src_wos->{$src}->{$next_cat} > $n_next_src) {
                $next_src = $src;
                $n_next_src = $src_wos->{$src}->{$next_cat};
            }
        }
        if($n_next_src == -1) {
            die "Cannot find a source for Web of Science category \"$next_cat\"\n";
        }
        push(@journals, $next_src);
        foreach my $cat (keys(%{$src_wos->{$next_src}})) {
            if(exists($$prog{$cat})) {
                $$prog{$cat} += $src_wos->{$next_src}->{$cat};
            }
        }
    }

    return @journals;
}

################################################################################
#                                                                              #
# ####  #####  ###  ####        ####   ###  ####  ##### ##### #   #            #
# #   # #     #   # #   #       #   #   #   #   #   #   #      # #             #
# ####  ####  ##### #   #       ####    #   ####    #   ####    #              #
# #   # #     #   # #   #       #   #   #   #   #   #   #      # #             #
# #   # ##### #   # ####        ####   ###  ####    #   ##### #   #            #
#                         #####                                                #
#                                                                              #
################################################################################

sub read_bibtex {
    my ($filename, $indexes, $bib, $dodgy) = @_;

    my @papers;
    my $n_dup = 0;
    my $n_missing = 0;
    my $n_dodgy = 0;
    my $n_extra_dodgy = 0;
    my %doi_ck;
    my $n = 0;
    my $prog_t = time();

    # Loop through all the papers
    foreach my $paper (&BibTeX::read_bib($filename)) {
        my $ok = 1;
        $n++;
        if(scalar(@papers) == 0) {
            $prog_t = time();
        }
        elsif(time() - $prog_t > $parameters{'R-progress-interval'}) {
            $prog_t = time();
            warn "PROGRESS [", &iso_date(), "]: Read $n records from $filename\n";
        }

        # Check the papers have all the required fields
        foreach my $field_OR (@required_fields) {
            my $present = 0;
            foreach my $field (@$field_OR) {
                my $wos_field = "_wos_$field";
                my $scopus_field = "_scopus_$field";
                if(exists($paper->{$field})) {
                    unless($field eq 'author' && $paper->{'author'} =~ /anonymous/i) {
                        $present = 1;
                    }
                }
                elsif(exists($paper->{$wos_field}) && exists($paper->{$scopus_field})) {
                    unless($field eq 'author' && ($paper->{'_wos_author'} =~ /anonymous/i
                        || $paper->{'_scopus_author'} =~ /anonymous/i))
                    {
                        $present = 1;
                        # This should not be necessary because slr-db-merge.pl should
                        # have chosen an entry. However it is necessary as at 2025-03-04.
                        $paper->{$field} = $paper->{$wos_field};
                    }
                }
            }
            if(!$present) {
                $missing_field_counts{join(' and ', @$field_OR)}++;
                $missing_field_counts{'_any_field'}++;
                $ok = 0;
                $n_missing++;
            }
        }

        # Check for duplicate DOI entries
        if($ok && exists(($paper->{'doi'}))) {
            my $doi = $paper->{'doi'};
            if(exists($dodgy->{$doi})) {
                $n_dodgy++;
            }
            elsif(exists($doi_ck{$doi})) {
                my $db_ix = $doi_ck{$doi};

                my $n_diff = &cmp_attr([$paper, $papers[$db_ix]], 0, 0, 1);
                if($n_diff == 0) {
                    $ok = 0;
                    $n_dup++;
                    &logbook("Ignoring repeat of paper with DOI \"$doi\" in \"$filename\"",
                        " with zero differences to former entry");
                    foreach my $field (keys(%$paper)) {
                        if(!exists($papers[$db_ix]->{$field})) {
                            $papers[$db_ix]->{$field} = $paper->{$field};
                            &logbook("Adding data from field $field (", $paper->{$field}, 
                                ") to existing entry with DOI \"$doi\"");
                        }
                    }
                }
                else {
                    delete($doi_ck{$doi});
                    $n_extra_dodgy++;
                    $n_dodgy++;
                    &logbook("Repeated entry of paper with DOI \"$doi\" found in \"$filename\"");
                }
            }
        }

        next if(!$ok);

        # Add extra fields for tidying. These have a double underscore in front.
        if(exists($paper->{'pages'})) {
            $paper->{'__pages'} = $paper->{'pages'};
            $paper->{'__pages'} =~ s/\s//g;
            $paper->{'__pages'} =~ s/\p{gc:pd}/-/g;
            $paper->{'__pages'} =~ s/-+/-/;
            $paper->{'__pages'} =~ s/-/--/;
        }

        $paper->{'__author'} = join(' and ', &BibTeX::clean_authors($paper));

        $paper->{'__source'} = exists($paper->{'journal'})
            ? uc($paper->{'journal'}) : uc($paper->{'booktitle'});
        $paper->{'__source'} =~ s/\\&/&/g;
        $paper->{'__source'} =~ s/^\s+//;
        $paper->{'__source'} =~ s/\s+$//;
        if(exists($journal_subs{$paper->{'__source'}})) {
            $paper->{'__source'} = $journal_subs{$paper->{'__source'}};
        }
        elsif(substr($paper->{'__source'}, 0, 5) eq 'JASSS') {
            $paper->{'__source'} = $journal_subs{'JASSS'};
        }
        if(!exists($abbrevj{$paper->{'__source'}})) {
            my $abbreviation;
            
            if(exists($paper->{'journal-iso'})) {
                $abbreviation = $paper->{'journal-iso'};
            }
            elsif(exists($paper->{'abbrev_source_title'})) {
                $abbreviation = $paper->{'abbrev_source_title'};
            }

            if(defined($abbreviation)) {
                $abbreviation =~ s/[^A-Za-z ]/ /g;
                $abbreviation =~ s/\s+/ /g;
                $abbreviation =~ s/^\s+//;
                $abbreviation =~ s/\s+$//;
                $abbrevj{$paper->{'__source'}} = $abbreviation;
            }
        }

        my @orig_src = &orig_hashes($paper);

        if(scalar(@orig_src) == 0) {
            &logbook("Paper ", $paper->{'_bibkey'},
                " has no identifiable 'original' source");
        }
        elsif(scalar(@orig_src) == 1) {
            $paper->{'__md5'} = md5_hex($orig_src[0]);
        }
        elsif(scalar(@orig_src) == 2) {
            $paper->{'_wos__md5'} = md5_hex($orig_src[0]);
            $paper->{'_scopus__md5'} = md5_hex($orig_src[1]);
        }
        else {
            die "BUG! Too many orig_src: ", scalar(@orig_src);
        }

        if(exists($paper->{'_scopus__filename'}) || exists($paper->{'_filename'})) {
            $paper->{'__asjc_cat'} = {};
            my $scopus_filename = (exists($paper->{'_scopus__filename'}) 
                ? $paper->{'_scopus__filename'} : $paper->{'_filename'}
            );
            foreach my $filename (split(/\s+AND\s+/, $scopus_filename)) {
                my @path = split(/\//, $filename);
                my $file = $path[$#path];

                if(exists($scopus_cats{$file})) {
                    $paper->{'__asjc_cat'}->{$scopus_cats{$file}}++
                        unless($scopus_cats{$file} eq 'NA');
                }
            }
        }
        else {
            &logbook("No filename entry found for a paper in $filename");
            $paper->{'__asjc_cat'} = {};
        }

        if(exists($paper->{'web-of-science-categories'})) {
            foreach my $category (split(/\s*;\s+/, $paper->{'web-of-science-categories'})) {
                $category =~ s/\\\&/and/g;
                $paper->{'__wos_cat'}->{$category}++;
            }
        }
        else {
            $paper->{'__wos_cat'} = {};
        }

        # Index the paper after adding it to the database
        push(@papers, $paper);
        my $ix = $#papers;
        if(exists($paper->{'doi'})) {
            my $doi = $paper->{'doi'};
            if(exists($dodgy->{$doi})) {
                push(@{$dodgy->{$doi}}, $ix);
            }
            else {
                $doi_ck{$doi} = $ix;
            }
        }
        $paper->{'__slr_id'} = $ix;
        $paper->{'__bibkey'} = &get_cite_key($paper);
        if(exists($paper->{'year'})) {
            my $y = $paper->{'year'};
            foreach my $sn (&BibTeX::author_surnames($paper)) {
                $sn = lc(&Latin::no_accents($sn));
                push(@{$bib->{uc($paper->{'__source'})}->{$y}->{$sn}}, $ix);
            }
        }

        foreach my $field (keys(%$indexes)) {
            my $index = $indexes->{$field};
            if(exists($paper->{$field})) {
                my $key = $paper->{$field};
                if($key eq '_bibkey') {
                    if(exists($index->{$key})) {
                        die "Duplicate citekey in BibTeX file \"$filename\": $key\n";
                    }
                    $index->{$key} = $ix;
                }
                else {
                    my %added;
                    my @fields = ($field);
                    push(@fields, "_wos_".$field, "_scopus_".$field) if($field !~ /^_/);
                    foreach my $f (@fields) {
                        next if(!exists($paper->{$f}));

                        $key = $paper->{$f};
                        $key = &TextTK::alns(&orig_text($key))
                            if($field eq 'title' || $field eq 'abstract');
                        $key = md5_hex($key) if($field eq 'abstract');
                        next if(exists($added{$key}));

                        $index->{$key}->{$ix}++;
                        $added{$key}++;
                    }
                }
            }
        }

    }
    &logbook("Read $n papers from \"$filename\", of which $n_missing were ",
        "rejected for having one or more missing fields, and $n_dup were ",
        "merged into other records with the same DOI.");
    &logbook("An array of size ", scalar(@papers), " is being returned, and ",
        "number read minus (number rejected plus number merged) is ",
        $n - ($n_missing + $n_dup));
    &logbook("Detected $n_dodgy dodgy DOIs, of which $n_extra_dodgy were ",
        "newly identified because the DOI was duplicated but there were ",
        "different entries in one or more common fields.");
    return @papers;
}

################################################################################
#                                                                              #
#  ###  ####   ###   ####       #   #  ###   #### #   # #####  ####            #
# #   # #   #   #   #           #   # #   # #     #   # #     #                #
# #   # ####    #   #  ##       ##### #####  ###  ##### ####   ###             #
# #   # #   #   #   #   #       #   # #   #     # #   # #         #            #
#  ###  #   #  ###   ####       #   # #   # ####  #   # ##### ####             #
#                         #####                                                #
#                                                                              #
################################################################################

sub orig_hashes {
    my ($paper) = @_;

    my ($wos_j, $scop_j) = ("", "");

    my $wos_title = exists($paper->{'_wos_title'}) ? $paper->{'_wos_title'}
        : (exists($paper->{'title'}) ? $paper->{'title'} : "");
    $wos_title = &orig_text($wos_title);

    if($wos_title ne "") {
        if(exists($paper->{'_wos_booktitle'})) {
            $wos_j = uc(&orig_text($paper->{'_wos_booktitle'}));
        }
        elsif(exists($paper->{'unique-id'}) && exists($paper->{'booktitle'})) {
            $wos_j = uc(&orig_text($paper->{'booktitle'}));
        }
        elsif(exists($paper->{'_wos_journal'})) {
            $wos_j = &orig_wos_journal($paper->{'_wos_journal'});
        }
        elsif(exists($paper->{'unique-id'}) && exists($paper->{'journal'})) {
            $wos_j = &orig_wos_journal($paper->{'journal'});
        }
    }

    my $scop_title = exists($paper->{'_scopus_title'}) ? $paper->{'_scopus_title'}
        : (exists($paper->{'title'}) ? $paper->{'title'} : "");
    $scop_title = &orig_text($scop_title);

    if($scop_title ne "") {
        if(exists($paper->{'_scopus_journal'})) {
            $scop_j = &orig_scopus_journal($paper->{'_scopus_journal'});
        }
        elsif(exists($paper->{'source'}) && $paper->{'source'} eq 'Scopus'
            && exists($paper->{'journal'})
        ) {
            $scop_j = &orig_scopus_journal($paper->{'journal'});
        }
    }

    my @rets;

    push(@rets, "${wos_title}${wos_j}")
        if($wos_j ne "" && ($wos_j ne $scop_j || $wos_title ne $scop_title));
    push(@rets, "${scop_title}${scop_j}") if($scop_j ne "");

    return @rets;
}

################################################################################
#                                                                              #
#  ###  ####   ###   ####       #   #  ###   ####                              #
# #   # #   #   #   #           #   # #   # #                                  #
# #   # ####    #   #  ##       # # # #   #  ###                               #
# #   # #   #   #   #   #       # # # #   #     #                              #
#  ###  #   #  ###   ####        # #   ###  ####                               #
#                         #####                   #####                        #
#                                                                              #
#  ####  ###  #   # ####  #   #  ###  #                                        #
#     # #   # #   # #   # ##  # #   # #                                        #
#     # #   # #   # ####  # # # ##### #                                        #
# #   # #   # #   # #   # #  ## #   # #                                        #
#  ###   ###   ###  #   # #   # #   # #####                                    #
#                                                                              #
################################################################################

sub orig_wos_journal {
    my ($txt) = @_;

    $txt = &orig_text($txt);
    $txt = "JASSS" if $txt =~ /JASSS/;
    $txt = "TRANSPORTATION RESEARCH PART A" if $txt =~ /transportation research part a/i;
    $txt = "TRANSPORTATION RESEARCH PART C" if $txt =~ /transportation research part c/i;

    return uc($txt);
}

################################################################################
#                                                                              #
#  ###  ####   ###   ####        ####  ####  ###  ####  #   #  ####            #
# #   # #   #   #   #           #     #     #   # #   # #   # #                #
# #   # ####    #   #  ##        ###  #     #   # ####  #   #  ###             #
# #   # #   #   #   #   #           # #     #   # #     #   #     #            #
#  ###  #   #  ###   ####       ####   ####  ###  #      ###  ####             #
#                         #####                                     #####      #
#                                                                              #
#  ####  ###  #   # ####  #   #  ###  #                                        #
#     # #   # #   # #   # ##  # #   # #                                        #
#     # #   # #   # ####  # # # ##### #                                        #
# #   # #   # #   # #   # #  ## #   # #                                        #
#  ###   ###   ###  #   # #   # #   # #####                                    #
#                                                                              #
################################################################################

sub orig_scopus_journal {
    my ($txt) = @_;

    $txt = &orig_text($txt);
    $txt = "PROCEEDINGS OF THE NATIONAL ACADEMY OF SCIENCES OF THE UNITED STATES OF" 
        if $txt =~ /PROCEEDINGS OF THE NATIONAL ACADEMY OF SCIENCES OF THE UNITED STATES OF/i;
    $txt = "SUSTAINABILITY" if $txt =~ /sustainability.*switzerland.*/i;
    $txt = "TRANSPORTATION RESEARCH PART A" if $txt =~ /transportation research part a/i;
    $txt = "TRANSPORTATION RESEARCH PART C" if $txt =~ /transportation research part c/i;

    return uc($txt);
}

################################################################################
#                                                                              #
# ####  #####  ###  ####         ####  ###  ####  ####  #   #  ####            #
# #   # #     #   # #   #       #     #   # #   # #   # #   # #                #
# ####  ####  ##### #   #       #     #   # ####  ####  #   #  ###             #
# #   # #     #   # #   #       #     #   # #   # #     #   #     #            #
# #   # ##### #   # ####         ####  ###  #   # #      ###  ####             #
#                         #####                                                #
#                                                                              #
################################################################################

sub read_corpus {
    my ($filename) = @_;

    my @papers;

    open(IN, "<:encoding(UTF-8)", $filename) or
        die "Error opening corpus file $filename: $!\n";

    my $headers = <IN>;
    my $sep = &CSV::set_header($headers);

    my $i_doi = &CSV::index("doi");
    my $i_journal = &CSV::index("journal");
    my $i_title = &CSV::index("title");
    my $i_cat = &CSV::index("categories");
    my $i_db = &CSV::index("db");
    my $i_abstract = &CSV::index("abstract");

    while (my $record = <IN>) {
        my @field = &CSV::split($record, $sep);

        my ($journal, $doi, $title, $db, $categories, $abstract) =
            ($field[$i_journal], $field[$i_doi], $field[$i_title], 
            $field[$i_db], $field[$i_cat], $field[$i_abstract]);

        $doi = "" if(!defined($doi));
        $doi = lc($doi);

        # Once again, we can't use &no_doi_id() here
        my $md5 = md5_hex($title.$journal);

        if($title eq 'Editorial: The use of logic in Agent-Based Social Simulation') {
            # See &read_screened() -- the MD5 was generated with 'Editorial: ' in the title
            my $orig_title = &orig_text($title);
            &logbook("Title \"$title\" in the corpus combination has been changed to \"$orig_title\". ",
                "See \"Corpus Papers Not Found by slr-review 20241123.md\" for the reason.");
            $title = $orig_title;
        }

        if($doi =~ /^[a-f0-9]+$/ && $md5 ne $doi) {
            # Check we generated the same DOI
            &logbook("Failed to duplicate the non-DOI ID of paper $doi in $filename ($md5)");
        }

        push(@papers, [ $doi, $md5, $db, $title, $abstract, $categories, uc($journal) ]);
    }
    close(IN);

    return @papers;
}

################################################################################
#                                                                              #
# ####  #####  ###  ####                                                       #
# #   # #     #   # #   #                                                      #
# ####  ####  ##### #   #                                                      #
# #   # #     #   # #   #                                                      #
# #   # ##### #   # ####                                                       #
#                         #####                                                #
#                                                                              #
#  ####  #### ####  ##### ##### #   # ##### ####                               #
# #     #     #   # #     #     ##  # #     #   #                              #
#  ###  #     ####  ####  ####  # # # ####  #   #                              #
#     # #     #   # #     #     #  ## #     #   #                              #
# ####   #### #   # ##### ##### #   # ##### ####                               #
#                                                                              #
################################################################################

sub read_screened {
    my ($filename) = @_;

    my @papers;

    open(IN, "<:encoding(UTF-8)", $filename) or
        die "Error opening screened papers file $filename: $!\n";

    my $headers = <IN>;
    my $sep = &CSV::set_header($headers);

    my $i_journal = &CSV::index("journal");
    my $i_doi = &CSV::index("doi");
    my $i_title = &CSV::index("title");
    my $i_abstract = &CSV::index("abstract");
    my $i_categories = &CSV::index("categories");
    my $i_db = &CSV::index("db");

    while ( my $record = <IN> ) {
        my @field = &CSV::split($record, $sep);

        my ($db, $journal, $doi, $title, $abstract, $categories) =
            ($field[$i_db], $field[$i_journal], $field[$i_doi], $field[$i_title], 
            $field[$i_abstract], $field[$i_categories]);

        $doi = join(",", &CSV::split($doi)) if substr($doi, 0, 1) eq "\"";
        $doi = lc($doi);
        $categories = join(",", &CSV::split($categories)) if substr($categories, 0, 1) eq "\"";

        # We need to remove start and end quotes from title and journal
        # if they are there in order to generate an ID properly
        $journal =~ s/\"//g; # We can be lazy with the journal cos none have quotes in
        $title = substr($title, 1, -1) if(substr($title, 0, 1) eq "\"" && substr($title, -1) eq "\"");
        $abstract = substr($abstract, 1, -1) if(substr($abstract, 0, 1) eq "\"" && substr($abstract, -1) eq "\"");

        # We cannot generate the ID using &no_doi_id() here
        my $md5 = md5_hex($title.$journal);

        if($title eq 'Editorial: The use of logic in Agent-Based Social Simulation') {
            # N.B. For this paper, the MD5 was generated with 'Editorial: ' in the title
            # so we generate the MD5 above first before shifting the title over so
            # we can pick up the match later
            my $orig_title = &orig_text($title);
            &logbook("Title \"$title\" in the corpus has been changed to \"$orig_title\". ",
                "See \"Corpus Papers Not Found by slr-review 20241123.md\" for the reason.");
            $title = $orig_title;
        }

        if($doi =~ /^[a-f0-9]+$/ && $md5 ne $doi) {
            # Check we generated the same DOI
            &logbook("Failed to duplicate the non-DOI ID of paper \"$doi\" in ",
                "screened papers file \"$filename\" ($md5)");
        }

        # Make the journal entry match what's on the Google Form
        if($journal eq "COMPUTERS ENVIRONMENT AND URBAN SYSTEMS") {
            $journal = "COMPUTERS, ENVIRONMENT AND URBAN SYSTEMS";
        }
        elsif($journal eq "JASSS") {
            $journal = "JOURNAL OF ARTIFICIAL SOCIETIES AND SOCIAL SIMULATION";
        }

        push(@papers, [ $doi, $md5, $db, $title, $abstract, $categories, uc($journal) ]);
    }

    close(IN);

    return @papers;
}

################################################################################
#                                                                              #
# ####  #####  ###  ####                                                       #
# #   # #     #   # #   #                                                      #
# ####  ####  ##### #   #                                                      #
# #   # #     #   # #   #                                                      #
# #   # ##### #   # ####                                                       #
#                         #####                                                #
#                                                                              #
#  ####  #### ####  ##### ##### #   #  ###  #   #  ####                        #
# #     #     #   # #     #     ##  #   #   ##  # #                            #
#  ###  #     ####  ####  ####  # # #   #   # # # #  ##                        #
#     # #     #   # #     #     #  ##   #   #  ## #   #                        #
# ####   #### #   # ##### ##### #   #  ###  #   #  ####                        #
#                                                                              #
################################################################################

sub read_screening {
    my ($json_file, $screen_db) = @_;

    my $json_txt = "";
    open(FP, "<:encoding(UTF-8)", $json_file) or die "Cannot open user JSON file $json_file: $!\n";
    while(my $line = <FP>) {
        $line =~ s/\s+$//;
        $json_txt .= "$line ";
    }
    close(FP);

    my $json = from_json($json_txt);
    my %results;

    foreach my $user (@$json) {
        my $name = $user->{'Name'};

        foreach my $paper (@{$user->{'Papers'}}) {
            my $doi = $paper->{'paper'};

            $doi = lc($doi);

            my @q = ($paper->{'q1'}, $paper->{'q2'}, $paper->{'q3'});

            if(exists($results{$doi})) {
                my $r = $results{$doi};
                for(my $i = 0; $i <= $#q; $i++) {
                    $$r[$i] += $q[$i];
                                    # Assumes JSON form stores 'Yes' as 1 and 'No' as 0
                                    # Which it does, of course
                }
            }
            else {
                $results{$doi} = [@q];
            }
        }
    }

    my @result;
    foreach my $id (keys(%results)) {
        my $q = $results{$id};

        my ($doi, $md5) = &doi_or_md5($id, $json_file, "screening");

        push(@result, [$doi, $md5, @$q]);
    }

    return @result;
}

################################################################################
#                                                                              #
# ####  #####  ###  ####                                                       #
# #   # #     #   # #   #                                                      #
# ####  ####  ##### #   #                                                      #
# #   # #     #   # #   #                                                      #
# #   # ##### #   # ####                                                       #
#                         #####                                                #
#                                                                              #
#  ###   ####  ####  ###   #### #   # ##### #   # #####  ####                  #
# #   # #     #       #   #     ## ## #     ##  #   #   #                      #
# #####  ###   ###    #   #  ## # # # ####  # # #   #    ###                   #
# #   #     #     #   #   #   # #   # #     #  ##   #       #                  #
# #   # ####  ####   ###   #### #   # ##### #   #   #   ####                   #
#                                                                              #
################################################################################

sub read_assignments {
    my ($filename) = @_;

    open(CSV, "<:encoding(UTF-8)", $filename) or
        die "Error opening SLR review assignment file $filename: $!\n";

    my $headers = <CSV>;
    my $sep = &CSV::set_header($headers);

    my @assigned;

    while(my $record = <CSV>) {
        my ($id, $paper, $r1, $r2) = &CSV::split($record, $sep);

        $id = lc($id);
        my ($doi, $md5) = &doi_or_md5($id);

        push(@assigned, [$doi, $md5, $r1, $r2]);
    }

    close(CSV);

    return @assigned;
}

################################################################################
#                                                                              #
# ####  #####  ###  ####        ####   ###  ####   #### #   #                  #
# #   # #     #   # #   #       #   # #   # #   # #      # #                   #
# ####  ####  ##### #   #       #   # #   # #   # #  ##   #                    #
# #   # #     #   # #   #       #   # #   # #   # #   #   #                    #
# #   # ##### #   # ####        ####   ###  ####   ####   #                    #
#                         #####                               #####            #
#                                                                              #
# ####   ###   ###   ####                                                      #
# #   # #   #   #   #                                                          #
# #   # #   #   #    ###                                                       #
# #   # #   #   #       #                                                      #
# ####   ###   ###  ####                                                       #
#                                                                              #
################################################################################

sub read_dodgy_dois {
    my ($filename, $dodgy) = @_;

    open(CSV, "<:encoding(UTF-8)", $filename) or
        die "Error opening SLR merge Dodgy DOI file $filename: $!\n";

    my $headers = <CSV>;
    my $sep = &CSV::set_header($headers);
    my $i_doi = &CSV::index('doi');
    my $i_n_scopus = &CSV::index('n.scopus');
    my $i_n_wos = &CSV::index('n.wos');

    while(my $record = <CSV>) {
        my @field = &CSV::split($record, $sep);

        my $doi = $field[$i_doi];
        if(exists($dodgy->{$doi})) {
            $dodgy->{$doi} = [$dodgy->{$doi}->[0] + $field[$i_n_scopus], $dodgy->{$doi}->[1] + $field[$i_n_wos]];
        }
        else {
            $dodgy->{$doi} = [$field[$i_n_scopus], $field[$i_n_wos]];
        }
    }

    close(CSV);
}

################################################################################
#                                                                              #
# ####  #####  ###  ####        ####  ##### #   #  ###  ##### #   #  ####      #
# #   # #     #   # #   #       #   # #     #   #   #   #     #   # #          #
# ####  ####  ##### #   #       ####  ####  #   #   #   ####  # # #  ###       #
# #   # #     #   # #   #       #   # #      # #    #   #     # # #     #      #
# #   # ##### #   # ####        #   # #####   #    ###  #####  # #  ####       #
#                         #####                                                #
#                                                                              #
################################################################################

sub read_reviews {
    my ($filename, $gform, $readers) = @_;

    open(CSV, "<:encoding(UTF-8)", $filename) or
        die "Error opening SLR review file $filename: $!\n";

    my $headers = <CSV>;
    my $sep = &CSV::set_header($headers);

    my @reviews;
    while ( my $record = <CSV> ) {
        my @field = &CSV::split($record, $sep);

        my @review;
        for(my $i = 0; $i <= $#CSV::header && $i <= $#field; $i++) {

            my $question = $CSV::header[$i];
            $field[$i] =~ s/^\s+//;
            $field[$i] =~ s/\s+$//;

            if(exists($$gform{$question})) {
                my $j = $$gform{$question};

                if($j == $GWHO) {
                    if(exists($$readers{$field[$i]})) {
                        $review[$j] = $$readers{$field[$i]};
                    }
                }
                elsif(length($field[$i]) == 0 || $field[$i] eq '""' || $field[$i] eq "N/A") {
                    $review[$j] = "NA";
                }
                else {
                    $review[$j] = $field[$i];
                }
            }
            else {
                &logbook("Google form question \"$question\" not recognized from file \"$filename\"");
            }
        }
        push(@reviews, [ @review ]);
    }
    close(CSV);

    return @reviews;
}

################################################################################
#                                                                              #
# ####   ###   ###         ###  ####        #   # ####  #####                  #
# #   # #   #   #         #   # #   #       ## ## #   # #                      #
# #   # #   #   #         #   # ####        # # # #   # ####                   #
# #   # #   #   #         #   # #   #       #   # #   #     #                  #
# ####   ###   ###         ###  #   #       #   # ####  ####                   #
#                   #####             #####                                    #
#                                                                              #
################################################################################

sub doi_or_md5 {
    my ($id, $filename, $filedesc) = @_;

    my $md5;
    my $doi;
    if($id =~ /^[a-f0-9]+$/) {
        $doi = "";
        $md5 = $id;
    }
    elsif($id =~ /\//) {
        $md5 = "";
        $doi = $id;
    }
    else {
        &logbook("Paper \"$id\" in $filedesc file \"$filename\" doesn't ",
            "look like a DOI or an MD5 hash");
        $doi = "";
        $md5 = "";
    }

    return ($doi, $md5);
}

################################################################################
#                                                                              #
#  ###  ####   ###   ####       ##### ##### #   # #####                        #
# #   # #   #   #   #             #   #      # #    #                          #
# #   # ####    #   #  ##         #   ####    #     #                          #
# #   # #   #   #   #   #         #   #      # #    #                          #
#  ###  #   #  ###   ####         #   ##### #   #   #                          #
#                         #####                                                #
#                                                                              #
# In the original programs used to generate and process data, the fields of    #
# the BibTeX files were processed in a different way, using procedures in      #
# Convert.pm. We need to replicate that to generate keys for documents with no #
# DOI. This extracts code from bib2csv.pl (as at 2024-11-20T10:59)             #
################################################################################

sub orig_text {
    my @args = @_;

    my @conv;

    foreach my $value (@args) {
        $value = &Convert::remove_unicode($value);
        $value = &Convert::spelling_errors($value);
        $value =~ s/^\s*//g;
        $value =~ s/\s\s*/ /g;
        $value =~ s/\\//g;
        push(@conv, $value);
    }

    if(scalar(@conv) == 1) {
        return $conv[0];
    }
    else {
        return @conv;
    }
}

################################################################################
#                                                                              #
# ####  ####   ###  #   # #####       ####  #####  ####  ###  ####  ####       #
# #   # #   #   #   ##  #   #         #   # #     #     #   # #   # #   #      #
# ####  ####    #   # # #   #         ####  ####  #     #   # ####  #   #      #
# #     #   #   #   #  ##   #         #   # #     #     #   # #   # #   #      #
# #     #   #  ###  #   #   #         #   # #####  ####  ###  #   # ####       #
#                               #####                                          #
#                                                                              #
################################################################################

sub print_record {
    my ($paper) = @_;

    foreach my $key (sort {$a cmp $b} keys(%$paper)) {
        my $value = $paper->{$key};
        if(length($value) + length($key) > 74) {
            print "$key = {", substr($value, 0, 70 - length($key)), "...}\n";
        }
        else {
            print "$key = {$value}\n";
        }
    }
}

##############################################################################
# print_bibtex
#
#  ####  ####   ###  #   # #####       ####   ###  ####  ##### ##### #   #
#  #   # #   #   #   ##  #   #         #   #   #   #   #   #   #      # # 
#  ####  ####    #   # # #   #         ####    #   ####    #   ####    #  
#  #     #   #   #   #  ##   #         #   #   #   #   #   #   #      # # 
#  #     #   #  ###  #   #   #         ####   ###  ####    #   ##### #   #
#                                #####                                    
#                                                                         
# BibTeX output to file pointer
##############################################################################

sub print_bibtex {
    my ($fp, $bib, @notes) = @_;

    my $key = &get_cite_key($bib);
    if(exists($bib->{'journal'})) {
        print $fp "\@article\{$key,\n";
        if(exists($bib->{'__author'})) {
            print $fp "  author = \{", &Latin::encode_latex($bib->{'__author'}), "\},\n";
        }
        else {
            print $fp "  author = \{Anon\},\n";
        }
        if(exists($bib->{'year'})) {
            print $fp "  year = \{", $bib->{'year'}, "\},\n";
        }
        else {
            print $fp "  year = \{no date\},\n";
        }
        if(exists($bib->{'title'})) {
            print $fp "  title = \{", &Latin::encode_latex($bib->{'title'}), "\},\n";
        }
        else {
            print $fp "  title = \{(Untitled)\},\n";
        }
        foreach my $entry ('journal', 'volume', 'number', '__pages', 'month') {

            my $key = $entry;
            $key =~ s/^__//;

            print $fp "  $key = \{", $bib->{$entry}, "\},\n" if exists($bib->{$entry});
        }
    }
    elsif(exists($bib->{'booktitle'})) {
        print $fp "\@inproceedings{$key,\n";
        if(exists($bib->{'__author'})) {
            print $fp "  author = \{", &Latin::encode_latex($bib->{'__author'}), "\},\n";
        }
        else {
            print $fp "  author = \{Anon\},\n";
        }
        print $fp "  year = \{", $bib->{'year'}, "\},\n" if exists($bib->{'year'});
        if(exists($bib->{'title'})) {
            print $fp "  title = \{", &latix::encode_latex($bib->{'title'}), "\},\n";
        }
        else {
            print $fp "  title = \{(Untitled)\},\n";
        }
        foreach my $entry ('editor', 'booktitle', 'volume', 'number', 'series', '__pages', 'month',
            'address', 'organization', 'publisher') {

            my $key = $entry;
            $key =~ s/^__//;

            print $fp "  $key = \{", $bib->{$entry}, "\},\n" if exists($bib->{$entry});
        }
    }
    elsif(exists($bib->{'_bibtype'})) {
        if(exists($bibtex_entries{$bib->{'_bibtype'}})) {
            print $fp "\@", $bib->{'_bibtype'}, "\{$key, \n";
            foreach my $entry (@{$bibtex_entries{$bib->{'_bibtype'}}}) {
                if(exists($bib->{$entry})) {
                    print $fp "  $entry = \{", $bib->{$entry}, "\},\n";
                }
                elsif(exists($bibtex_defaults{$entry})) {
                    print $fp "  $entry = \{$bibtex_defaults{$entry}\},\n";
                }
            }
        }
        else {
            warn "Unrecognized type: ", $bib->{'_bibtype'}, ": article not printed\n";
            return;
        }
    }
    else {
        print $fp "\@misc\{$key,\n";
        foreach my $entry ('author', 'year', 'title', 'address', 'institution', 'howpublished') {
            print $fp "  $entry = \{", $bib->{$entry}, "\},\n" if exists($bib->{$entry});
        }
        foreach my $bkey (sort {$a cmp $b} keys(%$bib)) {
            push(@notes, "BibTeX field: $bkey = ".$bib->{$bkey});
        }
        warn "No information we can use to print article, which had no journal, ",
            "booktitle or _bibtype entry\n";
    }
    
    print $fp "  doi = \{", $bib->{'doi'}, "\},\n" if exists($bib->{'doi'});

    if(scalar(@notes) > 1) {
        print $fp "  note = \{\n    ", join("\n    ", @notes), "\n  \},\n";
    }

    print $fp "  annote = \{SLR ID = ", $bib->{'__slr_id'}, "\}\n" if exists($bib->{'__slr_id'});
    print $fp "\}\n\n";
}

##############################################################################
# get_cite_key
#
#   #### ##### #####        ####  ###  ##### #####       #   # ##### #   #
#  #     #       #         #       #     #   #           #  #  #      # # 
#  #  ## ####    #         #       #     #   ####        ###   ####    #  
#  #   # #       #         #       #     #   #           #  #  #       #  
#   #### #####   #          ####  ###    #   #####       #   # #####   #  
#                    #####                         #####                  
#                                                                         
# Generate a cite key for a paper
##############################################################################

sub get_cite_key {
    my ($bib) = @_;

    if(exists($bib->{'__bibkey'})) {
        return $bib->{'__bibkey'};
    }
    my $key;
    if(exists($bib->{'__author'})) {
        my @aulist = split(/ and /, $bib->{'__author'});
        for(my $i = 0; $i <= $#aulist && $i < $parameters{'R-bib-max-auth'}; $i++) {
            $aulist[$i] =~ s/^\s+//;
            $aulist[$i] =~ s/\s+$//;
            my @auth = split(",", $aulist[$i]);
            my $surname = $auth[0];
            if(scalar(@auth) == 1) {
                @auth = split(" ", $aulist[$i]);
                $surname = $auth[0];
            }
            $surname =~ s/^\s+//;
            $surname =~ s/\s+$//;
            $surname =~ s/\s+/_/g;
            $surname =~ s/[^A-Za-z]//g;

            $key .= "_" if $i > 0;
            $key .= $surname;
        }
        $key .= "_et_al" if scalar(@aulist) > $parameters{'R-bib-max-auth'};
    }
    else {
        $key = "Anon";
    }

    if(exists($bib->{'year'})) {
        $key .= "_".$bib->{'year'};
    }
    else {
        $key .= "_No_Date";
    }

    if(exists($bib->{'title'})) {
        my @title = split(" ", $bib->{'title'});
        while(scalar(@title) > $parameters{'R-bib-max-twords'}) {
            pop(@title);
        }
        for(my $i = 0; $i <= $#title; $i++) {
            $title[$i] =~ s/[^A-z]//g;
        }
        $key .= "_".(join("_", @title));
    }
    else {
        $key .= "_Untitled";
    }

    $key = &Latin::no_accents($key);
    $key =~ s/!/_/g;

    my $n = 0;
    my $key_n = $key;
    while(exists($citekeys{$key_n})) {
        $n++;
        $key_n = "${key}_$n";
    }

    $citekeys{$key_n} = $bib;

    return $key_n;
}

################################################################################
#                                                                              #
# ####  ####         ###  #   #  ###  #     #   #  #### #####                  #
# #   # #   #       #   # ##  # #   # #      # #  #     #                      #
# #   # ####        ##### # # # ##### #       #    ###  ####                   #
# #   # #   #       #   # #  ## #   # #       #       # #                      #
# ####  ####        #   # #   # #   # #####   #   ####  #####                  #
#             #####                                                            #
#                                                                              #
################################################################################

sub db_analyse {
    my ($lost, $dbase, $i, $desc, $db_str) = @_;

    my %counts;

    foreach my $entry (@$lost) {
        my $value = $dbase->[$entry]->[$i];
        if($i == $R_DOI) {
            if($value =~ /^[a-f0-9]+$/) {
                $counts{'md5'}++;
            }
            elsif($value =~ /^\s*$/) {
                $counts{'empty'}++;
            }
            elsif($value =~ /\//) {
                $counts{'doi'}++;
                &logbook("$value") if $counts{'doi'} < 20;
            }
            else {
                $counts{'dunno'}++;
            }
        }
        elsif($i == $R_TTL || $i == $R_ABS) {
            my %chars;
            foreach my $chr (split(//, $value)) {
                $counts{$chr}++ if(!exists($chars{$chr}));
                $chars{$chr}++;
            }
        }
        elsif($i == $R_CAT) {
            foreach my $cat (split(/;/, lc($value))) {
                $cat =~ s/^\s+//;
                $cat =~ s/\s+$//;

                $counts{$cat}++;
            }
        }
        else {
            $counts{$value}++;
        }
    }

    &logbook("$desc counts for unmatched $db_str:");
    foreach my $c (sort {$a cmp $b} keys(%counts)) {
        &logbook("\t$c: ", $counts{$c});
    }
}

################################################################################
#                                                                              #
# ####  ##### ####   ###  ####  #####                                          #
# #   # #     #   # #   # #   #   #                                            #
# ####  ####  ####  #   # ####    #                                            #
# #   # #     #     #   # #   #   #                                            #
# #   # ##### #      ###  #   #   #                                            #
#                                     #####                                    #
#                                                                              #
# #      ###   ###  #   # #   # ####        #   #  ####  ###   #### #####      #
# #     #   # #   # #  #  #   # #   #       #   # #     #   # #     #          #
# #     #   # #   # ###   #   # ####        #   #  ###  ##### #  ## ####       #
# #     #   # #   # #  #  #   # #           #   #     # #   # #   # #          #
# #####  ###   ###  #   #  ###  #            ###  ####  #   #  #### #####      #
#                                     #####                                    #
#                                                                              #
################################################################################

sub report_lookup_usage {
    my ($name) = @_;

    foreach my $f (keys(%lookup_wins)) {
        $lookup_loss{$f} = 0 if(!exists($lookup_loss{$f}));
    }
    foreach my $f (keys(%lookup_loss)) {
        $lookup_wins{$f} = 0 if(!exists($lookup_wins{$f}));
    }

    &logbook("Index usage looking up $name:");
    foreach my $field (sort {$a cmp $b} keys(%lookup_wins)) {
        &logbook("\t$field: ", $lookup_wins{$field}, " wins; ",
            $lookup_loss{$field}, " fails");
        $lookup_wins{$field} = 0;
        $lookup_loss{$field} = 0;
    }

}

################################################################################
#                                                                              #
#  #### #   # ####         ###  ##### ##### ####                               #
# #     ## ## #   #       #   #   #     #   #   #                              #
# #     # # # ####        #####   #     #   ####                               #
# #     #   # #           #   #   #     #   #   #                              #
#  #### #   # #           #   #   #     #   #   #                              #
#                   #####                                                      #
#                                                                              #
################################################################################

sub cmp_attr {
    my ($db, $log, @opt_ix) = @_;

    my %attr;
    foreach my $ix (@opt_ix) {
        my $paper = $$db[$ix];
        foreach my $field (keys(%$paper)) {
            push(@{$attr{$field}->{lc($paper->{$field})}}, $ix);
        }
    }
    my $n_diff = 0;
    foreach my $field (sort {$a cmp $b} keys(%attr)) {
        my @entries = keys(%{$attr{$field}});
        next if(scalar(@entries) == scalar(@opt_ix));
        if(scalar(@entries) > 1) {
            foreach my $entry (@entries) {
                my $ixes = $attr{$field}->{$entry};
                if($log) {
                    &logbook("$field:", join(", ", sort {$a <=> $b} @$ixes), "> $entry");
                }
            }
            $n_diff++;
        }
    }

    return $n_diff;
}

################################################################################
#                                                                              #
#  ###   ####  ####  ###   #### #   #                                          #
# #   # #     #       #   #     ##  #                                          #
# #####  ###   ###    #   #  ## # # #                                          #
# #   #     #     #   #   #   # #  ##                                          #
# #   # ####  ####   ###   #### #   #                                          #
#                                     #####                                    #
#                                                                              #
# #####  ###  ####   ###   ####  ####                                          #
#   #   #   # #   #   #   #     #                                              #
#   #   #   # ####    #   #      ###                                           #
#   #   #   # #       #   #         #                                          #
#   #    ###  #      ###   #### ####                                           #
#                                                                              #
################################################################################

sub assign_topics {
    my ($papers) = @_;

    my @topics = (
        ['ABM', 'agent', 'based', 'model'],
        ['ABM', 'agent', 'based', 'models'],
        ['ABM', 'agent', 'based', 'modelling'],
        ['ABM', 'agent', 'based', 'modeling'],
        ['ABS', 'agent', 'based', 'simulation'],
        ['ABS', 'agent', 'based', 'simulations'],
        ['ABSS', 'agent', 'based', 'social', 'simulation'],
        ['ABSS', 'agent', 'based', 'social', 'simulations'],
        ['IBM', 'individual', 'based', 'model'],
        ['IBM', 'individual', 'based', 'models'],
        ['IBM', 'individual', 'based', 'modelling'],
        ['IBM', 'individual', 'based', 'modeling'],
        ['Micro', 'microsimulation'],
        ['Micro', 'microsimulations'],
        ['Micro', 'micro', 'simulation'],
        ['Micro', 'micro', 'simulations'],
        ['MAM', 'multi', 'agent', 'model'],
        ['MAM', 'multi', 'agent', 'models'],
        ['MAM', 'multi', 'agent', 'modelling'],
        ['MAM', 'multi', 'agent', 'modeling'],
        ['MAM', 'multiagent', 'model'],
        ['MAM', 'multiagent', 'models'],
        ['MAM', 'multiagent', 'modelling'],
        ['MAM', 'multiagent', 'modeling'],
        ['MAS', 'multi', 'agent', 'system'],
        ['MAS', 'multi', 'agent', 'systems'],
        ['MAS', 'multiagent', 'system'],
        ['MAS', 'multiagent', 'systems'],
        ['MABS', 'multi', 'agent', 'based', 'simulation'],
        ['MABS', 'multi', 'agent', 'based', 'simulations'],
        ['MAsim', 'multiagent', 'simulation'],
        ['MAsim', 'multiagent', 'simulations'],
        ['MAsim', 'multi', 'agent', 'simulation'],
        ['MAsim', 'multi', 'agent', 'simulations'],
        ['Agents.jl', 'agents', 'jl'],
        ['GAMA', 'gama'],
        ['MASON', 'mason'],
        ['NetLogo', 'netlogo'],
        ['Repast', 'repast'],
        ['Swarm', 'swarm'],
        ['FLAMEGPU', 'flamegpu'],
        ['Agent', 'agent']
    );

    my $n_no_topics = 0;
    my $n_no_topics_intent = 0;
    foreach my $paper (@$papers) {

        my $title;
        if(exists($paper->{'title'})) {
            $title = $paper->{'title'};
        }

        my $abstract;
        if(exists($paper->{'abstract'})) {
            $abstract = $paper->{'abstract'};
        }
        my $keywords;
        if(exists($paper->{'keywords'})) {
            $keywords = $paper->{'keywords'};
        }
        if(exists($paper->{'author_keywords'})) {
            $keywords = defined($keywords) ? "$keywords; ".$paper->{'author_keywords'}
                : $paper->{'author_keywords'};
        }

        my %found = &topic_search($title, $abstract, $keywords, @topics);
        my $has_agent = exists($found{'Agent'});

        foreach my $topic (keys(%found)) {
            next if $topic eq 'Agent';

            if(exists($sw_topics{$topic})) {
                if($sw_topics{$topic} == 1) {
                    if($has_agent) {
                        $paper->{'__topics'}->{$topic} = 1;
                        $paper->{'__topics_intent'}->{$topic} = 1;
                    }
                }
                else {
                    $paper->{'__topics'}->{$topic} = 1;
                    if($has_agent) {
                        $paper->{'__topics_intent'}->{$topic} = 1;
                    }
                }
            }
            else {
                $paper->{'__topics'}->{$topic} = 1;
                $paper->{'__topics_intent'}->{$topic} = 1;
            }
        }

        if(!exists($paper->{'__topics_intent'})) {
            $paper->{'__topics_intent'} = {};
            $n_no_topics_intent++;
            if(!exists($paper->{'__topics'})) {
                $paper->{'__topics'} = {};
                $n_no_topics++;
            }
        }
    }

    return ($n_no_topics, $n_no_topics_intent);
}

################################################################################
#                                                                              #
# #####  ###  ####   ###   ####        #### #####  ###  ####   #### #   #      #
#   #   #   # #   #   #   #           #     #     #   # #   # #     #   #      #
#   #   #   # ####    #   #            ###  ####  ##### ####  #     #####      #
#   #   #   # #       #   #               # #     #   # #   # #     #   #      #
#   #    ###  #      ###   ####       ####  ##### #   # #   #  #### #   #      #
#                               #####                                          #
#                                                                              #
################################################################################

sub topic_search {
    my ($title, $abstract, $keywords, @topic) = @_;

    my @search;

    push(@search, $title) if(defined($title) && $title =~ /\w/);
    push(@search, $abstract) if(defined($abstract) && $title =~ /\w/);
    if(defined($keywords)) {
        foreach my $kw (split(/;\s*/, $keywords)) {
            push(@search, $kw) if $kw =~ /\w/;
        }
    }

    my %found_topics;

    for(my $i = 0; $i <= $#search; $i++) {
        my $txt = lc($search[$i]);

        $txt = &Latin::no_accents($txt);
        $txt =~ s/[^a-z]/ /g;
        $txt =~ s/\s+/ /g;

        my @words = split(" ", $txt);

        my @topic_counter;
        my @topic_n;
        for(my $j = 0; $j <= $#topic; $j++) {
            $topic_counter[$j] = 0;
            $topic_n[$j] = scalar(@{$topic[$j]}) - 1;
        }

        for(my $k = 0; $k <= $#words; $k++) {
            my $word = $words[$k];

            for(my $j = 0; $j <= $#topic; $j++) {
                my $h = $topic_counter[$j] + 1; # The first one is the shorthand
                
                if($h <= $topic_n[$j]) {
                    my $topic_word = $topic[$j]->[$h];

                    if($topic_word eq $word) {
                        if($h == $topic_n[$j]) {
                            # We've reached the end of the topic word list
                            # So add the shorthand topic to the found topics
                            # and reset the counter
                            $found_topics{$topic[$j]->[0]}++;
                            $topic_counter[$j] = 0;
                        }
                        else {
                            # Not there yet, so increment the counter
                            $topic_counter[$j]++;
                        }
                    }
                    else {
                        # Word not equal, reset the counter
                        $topic_counter[$j] = 0;
                    }
                }
            }
        }
    }

    return %found_topics;
}

################################################################################
#                                                                              #
# ####  ####   ###  #   # #####       ####  ####   ###   #### #   #  ###       #
# #   # #   #   #   ##  #   #         #   # #   #   #   #     ## ## #   #      #
# ####  ####    #   # # #   #         ####  ####    #    ###  # # # #####      #
# #     #   #   #   #  ##   #         #     #   #   #       # #   # #   #      #
# #     #   #  ###  #   #   #         #     #   #  ###  ####  #   # #   #      #
#                               #####                                          #
#                                                                              #
################################################################################

sub print_prisma {
    my ($filename, $wos, $scopus, $record_merge, $wos_categories, $screening, $assessed, $included) = @_;
    #              Scalar  Hash   Scalar         Scalar           Array       Array      Scalar

    my $fp;
    open($fp, '>:encoding(UTF-8)', $filename) or die "Cannot create prisma file $filename: $!\n";

    print $fp "% in preamble, please add \\usepackage{prisma-flow-diagram}\n\n";

    my $tab = " " x 4;
    my $tab_tab = " " x 8;
    # Preamble
    print $fp "\\begin{figure}\n";
    print $fp "$tab\\resizebox{\\textwidth}{!}{\n";
    print $fp "$tab_tab\\prismaflowstart\n";

    # Search and merge

    print $fp "\n$tab_tab% Search and merge\n";
    print $fp "$tab_tab\\prismaflownode{wos}{left=of tc}{Records downloaded ",
        "from Web of Science (n = $wos)}{}\n";
    print $fp "$tab_tab\\prismaflownode{merge}{below=of tc |- wos.south}",
        "{Records after duplicates removed (n = $record_merge)}{wos}\n";
    print $fp "$tab_tab\\prismaflownode{unselect}{right=of merge}",
        "{Records excluded (n = ", ($record_merge - $wos_categories), ")}{merge}\n";
    print $fp "$tab_tab\\prismaflownode{scopus}{above=of unselect}{Records downloaded from Scopus";
    foreach my $asjc (sort {$a cmp $b} keys(%$scopus)) {
        print $fp "\\\\\n$tab_tab$tab$asjc (n = ", $scopus->{$asjc}, ")";
    }
    print $fp "}{}\n";

    # Merge

    print $fp "$tab_tab\\prismaflowarrow{scopus}{merge}\n";

    # Selection

    print $fp "\n$tab_tab% Selection\n";
    print $fp "$tab_tab\\prismaflownode{select}{below=of merge}",
        "{Records after Web of Science categories selected (n = $wos_categories)}{merge}\n";
    print $fp "$tab_tab\\prismaflownode{unscreen}{right=of select}",
        "{Records excluded (n = ", ($wos_categories - $$screening[0]), ")}{select}\n";

    # Screen

    print $fp "\n$tab_tab% Screening\n";
    print $fp "$tab_tab\\prismaflownode{screen}{below=of select}",
        "{Records screened from\\\\selected journals (n = ", $$screening[0], ")}{select}\n";
    print $fp "$tab_tab\\prismaflownode{unreview}{right=of screen}",
        "{Records excluded (n = ", ($$screening[1] + $$screening[2] + $$screening[3]),
        ")\\\\\n$tab_tab${tab}Not an ABM (n = ", $$screening[1], ")\\\\\n",
        "$tab_tab${tab}Not social sciences (n = ", $$screening[2], ")\\\\\n",
        "$tab_tab${tab}Not empirical (n = ", $$screening[3], ")}{screen}\n";

    # Eligibility

    print $fp "\n$tab_tab% Review\n";
    print $fp "$tab_tab\\prismaflownode{review}{below=of screen}",
        "{Records reviewed (n = ", $$assessed[0], ")}{screen}\n";
    print $fp "$tab_tab\\prismaflownode{uninclude}{right=of review}",
        "{Records excluded (n = ", ($$assessed[1] + $$assessed[2] + $$assessed[3] + $$assessed[4]),
        ")\\\\\n$tab_tab${tab}Not an ABM (R1) (n = ", $$assessed[1], ")\\\\\n",
        "$tab_tab${tab}Not social sciences (R2) (n = ", $$assessed[2], ")\\\\\n",
        "$tab_tab${tab}Not empirical (R3) (n = ", $$assessed[3], ")\\\\\n",
        "$tab_tab${tab}R4 is N/A (n = ", $$assessed[4], ")}{review}\n";

    # Included

    print $fp "\n$tab_tab% Included\n";
    print $fp "$tab_tab\\prismaflownode{include}{below=of review}",
        "{Records included (n = ", $included, ")}{review}\n";

    # Labels

    print $fp "$tab_tab% Labels at the side\n";
    print $fp "$tab_tab\\prismalabel{1.3 * \\mh}{wos.west |- {\$(wos)!0.5!(merge)\$}}{Identification};\n";
    print $fp "$tab_tab\\prismalabel{1.3 * \\mh}{wos.west |- {\$(select)!0.5!(screen)\$}}{Screening};\n";
    print $fp "$tab_tab\\prismalabel{1.3 * \\mh}{wos.west |- review}{Eligibility};\n";
    print $fp "% Uncomment if you want the Included label -- it overlaps with Eligibility though\n";
    print $fp "\%$tab_tab\\prismalabel{1.3 * \\mg}{wos.west |- include}{Included};\n";

    # Closedown
    print $fp "\n$tab_tab\\prismaflowend\n";
    print $fp "$tab}\n";
    print $fp "$tab\\caption{PRISMA Flow Diagram}\n";
    print $fp "$tab\\label{fig:prisma}\n";
    print $fp "\\end{figure}\n";

    close($fp);
}

################################################################################
#                                                                              #
# ####        ####  ####   ###  #   # #####                                    #
# #   #       #   # #   #   #   ##  #   #                                      #
# ####        ####  ####    #   # # #   #                                      #
# #   #       #     #   #   #   #  ##   #                                      #
# #   #       #     #   #  ###  #   #   #                                      #
#       #####                               #####                              #
#                                                                              #
#  #### #      ###  ####   ###  #      ####                                    #
# #     #     #   # #   # #   # #     #                                        #
# #  ## #     #   # ####  ##### #      ###                                     #
# #   # #     #   # #   # #   # #         #                                    #
#  #### #####  ###  ####  #   # ##### ####                                     #
#                                                                              #
################################################################################

sub r_print_globals {
    my ($r_fp, $args, $files, $params, $pdfs) = @_;

    my %vars;
    my %types;
    my @file_list;
    foreach my $file (sort {$a cmp $b} keys(%$files)) {
        next if(!$parameters{'R-do-sankey'} && $file =~ /^sankey/);
        next if(!$parameters{'R-do-cloud'} && $file =~ /^cloud/);
        next if(!$parameters{'R-do-table-mi'} && $file =~ /^table-mi/);
        push(@file_list, $file) if($file !~ /^R/);
    }
    my @param_list;
    foreach my $param (sort {$a cmp $b} keys(%$params)) {
        push(@param_list, $param) if($param !~ /^R/);
    }
    my @pdf_list;
    foreach my $pdf (sort {$a cmp $b} keys(%$pdfs)) {
        push(@pdf_list, $pdf) if($pdf !~ /^R/);
    }

    foreach my $file (@file_list) {
        my $var = $file;
        $var =~ s/-/./g;
        $vars{$file} = $var;
        print $r_fp "$var = \"", $files->{$file}, "\"\n";
        $types{$var} = 'character';
    }
    print $r_fp "\n";
    foreach my $param (@param_list) {
        my $var = $param;
        $var =~ s/-/./g;
        die "BUG! param $param over-writes R var $var!\n" if(exists($vars{$var}));
        $vars{$param} = $var;
        my $value = $params->{$param};
        if(exists($boolean_param{$param})) {
            $value = $value ? "TRUE" : "FALSE";
            print $r_fp "$var = $value\n";
            $types{$var} = 'logical';
        }
        elsif($value =~ /^\d+(\.\d+)?$/) {
            print $r_fp "$var = $value\n";
            $types{$var} = 'numeric';
        }
        else {
            print $r_fp "$var = \"$value\"\n";
            $types{$var} = 'character';
        }
    }
    print $r_fp "\n";
    my %pdf_files;
    foreach my $pdf (@pdf_list) {
        my $var = $pdf;
        $var =~ s/-/./g;
        die "BUG! pdf $pdf over-writes R var $var!\n" if(exists($vars{$var}));
        $vars{$pdf} = $var;
        my $value = $pdfs->{$pdf};
        die "PDF file \"$value\" set by option \"$pdf\" overwrites option \"",
            $pdf_files{$value}, "\"" if(exists($pdf_files{$value}));
        $pdf_files{$value} = $pdf;
        print $r_fp "$var = \"$value\"\n";
    }
    print $r_fp "\n\nlogbook <- function(...) {\n";
    print $r_fp "    cat(\"", ${output_files{'R-script'}}, " log (\", ",
        "format(Sys.time(), \"\%Y-\%m-\%dT\%H:\%M:\%S\"), \"): \", ..., \"\\n\", sep = \"\")\n";
    print $r_fp "}\n";

    print $r_fp "# Palettes checked for being colourblind friendly (ish)\n";
    print $r_fp "# See https://www.color-blindness.com/coblis-color-blindness-simulator/\n\n";

    print $r_fp "hpc.pal = as.list(rainbow(6, s = 0.75 - 1:4 / 8, v = 0.25 + 1:4 / 6)[1:4])\n";
    print $r_fp "names(hpc.pal) = c(\"yes\", \"no\", \"maybe\", \"empty\")\n";
    print $r_fp "hpc.pal\$all = \"#443400\"\n";
    print $r_fp "\t\t\t# HPC: yes, no, maybe, NA, all\n\n";

    print $r_fp "tl.pal = as.list(rainbow(3, s = c(0.8, 0.6, 0.8), v = c(0.4, 0.8, 0.6), end = 0.3))\n";
    print $r_fp "names(tl.pal) = c(\"red\", \"amber\", \"green\")\n";
    print $r_fp "\t\t\t# Traffic light palette\n\n";

    print $r_fp "lit.pal = as.list(rainbow(6, s = 0.3 + 1:6 / 10, v = c(0.3, 0.6, 0.4, 0.8, 0.5, 0.9), ",
        "start = 0.01, end = 0.9))\n";
    print $r_fp "names(lit.pal) = c(\"", join("\", \"", @stages), "\")\n";
    print $r_fp "\t\t\t# Different stages of the literature review\n\n";

    print $r_fp "cs.pal = as.list(rainbow(2, s = c(0.7, 0.3), v = c(0.7, 0.3), start = 0.05, end = 0.6))\n";
    print $r_fp "names(cs.pal) = c(\"comp\", \"soc\")\n";
    print $r_fp "\t\t\t# Computing science / social science palette\n\n";
    
    if($args) {
        print $r_fp "\n# Process command line arguments\n\nargs <- commandArgs(TRUE)\n\n";
        print $r_fp "if(length(args) > 0 && (args[1] == \"--help\" || args[1] == \"--usage\")) {\n";
        print $r_fp "    cat(\"Usage: ", ${output_files{'R-script'}}, "\"";
        foreach my $file (@file_list) {
            my $filename = $files->{$file};
            my @nameparts = split(/\./, $filename);
            my $filetype = (scalar(@nameparts) >= 2) ? uc($nameparts[$#nameparts])." file" : "file name";
            print $r_fp ",\n        \" [--$file <$filetype>]\"";
        }
        foreach my $param (@param_list) {
            if($types{$vars{$param}} eq 'logical') {
                print $r_fp ",\n        \" [--with-$param] [--no-$param]\"";
            }
            else {
                print $r_fp ",\n        \" [--$param <",
                    (($types{$vars{$param}} eq 'numeric') ? "n" : "value"),
                    ">]\"";
            }
        }
        foreach my $pdf (@pdf_list) {
            print $r_fp ",\n        \" [--$pdf <pdf-file>]\"";
        }
        print $r_fp ",\n        \"\\n\", sep = \"\")\n\n";

        print $r_fp "    cat(\"\\tDefaults:\"";
        foreach my $file (@file_list) {
            print $r_fp ",\n        \"\\n\\t\\t$file: \", ", $vars{$file};
        }
        foreach my $param (@param_list) {
            print $r_fp ",\n        \"\\n\\t\\t$param: \", ", $vars{$param};
        }
        foreach my $pdf (@pdf_list) {
            print $r_fp ",\n        \"\\n\\t\\t$pdf: \", ", $vars{$pdf};
        }
        print $r_fp ",\n        \"\\n\", sep = \"\")\n\n";

        print $r_fp "    q(status = 0)\n}\n\n";
        print $r_fp "while(length(args) > 0) {\n";
        print $r_fp "    opt <- args[1]\n";
        print $r_fp "    args <- tail(args, n = -1)\n\n";

        my $first = 1;

        foreach my $file (@file_list) {
            if($first) {
                print $r_fp "    if(";
                $first = 0;
            }
            else {
                print $r_fp "    } else if(";
            }
            print $r_fp "opt == \"--$file\") {\n";
            print $r_fp "        ", $vars{$file}, " = args[1]\n";
            print $r_fp "        args <- tail(args, n = -1)\n";
        }
        foreach my $param (@param_list) {
            if($types{$vars{$param}} eq 'logical') {
                print $r_fp "    } else if(opt == \"--no-$param\") {\n";
                print $r_fp "        ", $vars{$param}, " = FALSE\n";
                print $r_fp "    } else if(opt == \"--with-$param\") {\n";
                print $r_fp "        ", $vars{$param}, " = TRUE\n";
            }
            else {
                print $r_fp "    } else if(opt == \"--$param\") {\n";
                print $r_fp "        ", $vars{$param}, " = ";
                if($types{$vars{$param}} eq 'numeric') {
                    print $r_fp "as.numeric(args[1])\n";
                }
                else {
                    print $r_fp "args[1]\n";
                }
                print $r_fp "        args <- tail(args, n = -1)\n";
            }
        }
        foreach my $pdf (@pdf_list) {
            print $r_fp "    } else if(opt == \"--$pdf\") {\n";
            print $r_fp "        ", $vars{$pdf}, " = args[1]\n";
            print $r_fp "        args <- tail(args, n = -1)\n";
        }

        print $r_fp "    } else {\n";
        print $r_fp "        stop(\"Option \", opt, \" not recognized. ",
            "Try --help for usage.\", call. = FALSE)\n";
        print $r_fp "    }\n}\n\n";

        foreach my $file (@file_list) {
            my $text = $file;
            $text =~ s/-/ /g;
            if($text !~ /file/) {
                $text .= " file";
            }
            print $r_fp "logbook(\"$text: \", ", $vars{$file}, ")\n";
        }
        foreach my $param (@param_list) {
            my $text = $param;
            $text =~ s/-/ /g;
            print $r_fp "logbook(\"$text: \", ", $vars{$param}, ")\n";
        }
        foreach my $pdf (@pdf_list) {
            my $text = $pdf;
            $text =~ s/-/ /g;
            print $r_fp "logbook(\"$text: \", ", $vars{$pdf}, ")\n";
        }
    }
    if($parameters{'R-overdate'} && !$parameters{'R-overwrite'}) {
        print $r_fp "if(dir.exists(output.dir)) {\n";
        print $r_fp "    iso.date = format(Sys.time(), \"\%Y-\%m-\%d\")\n";
        print $r_fp "    iso.date.time = format(Sys.time(), \"\%Y-\%m-\%dT\%H-\%M-\%S\")\n";
        print $r_fp "    if(!dir.exists(paste(output.dir, iso.date, sep = \"-\"))) {\n";
        print $r_fp "        output.dir = paste(output.dir, iso.date, sep = \"-\")\n";
        print $r_fp "    } else if(!dir.exists(paste(output.dir, iso.date.time, sep = \"-\"))) {\n";
        print $r_fp "        output.dir = paste(output.dir, iso.date.time, sep = \"-\")\n";
        print $r_fp "    } else {\n";
        print $r_fp "        stop(\"Cannot create a non-existent output directory. ",
            "Try again.\", call. = FALSE)\n";
        print $r_fp "    }\n}\n\n";
    }
    print $r_fp "if(!dir.exists(output.dir)) {\n    dir.create(output.dir)\n}\n\n";

    print $r_fp "if(tex.dir == \".\") {\n    tex.dir = output.dir\n} else {\n",
        "    tex.dir = paste(output.dir, tex.dir, sep = \"/\")\n";
    print $r_fp "    if(!dir.exists(tex.dir)) {\n        dir.create(tex.dir)\n    }\n}\n\n";

    print $r_fp "if(pdf.dir == \".\") {\n    pdf.dir = output.dir\n} else {\n",
        "    pdf.dir = paste(output.dir, pdf.dir, sep = \"/\")\n";
    print $r_fp "    if(!dir.exists(pdf.dir)) {\n        dir.create(pdf.dir)\n    }\n}\n\n";

    if($parameters{'R-do-sankey'}) {
        print $r_fp "if(sankey.dir == \".\") {\n    sankey.dir = output.dir\n} else {\n";
        print $r_fp "    sankey.dir = paste(output.dir, sankey.dir, sep = \"/\")\n";
        print $r_fp "    if(!dir.exists(sankey.dir)) {\n        dir.create(sankey.dir)\n",
            "    }\n}\n\n";
    }
    if($parameters{'R-do-cloud'}) {
        print $r_fp "if(cloud.dir == \".\") {\n    cloud.dir = output.dir\n} else {\n";
        print $r_fp "    cloud.dir = paste(output.dir, cloud.dir, sep = \"/\")\n";
        print $r_fp "    if(!dir.exists(cloud.dir)) {\n        dir.create(cloud.dir)\n",
            "    }\n}\n\n";
    }
    foreach my $file (@file_list) {
        if($file =~ /^sankey/) {
            print $r_fp $vars{$file}, " = paste(sankey.dir, ", $vars{$file},
                ", sep = \"/\")\n";
        }
        elsif($file =~ /^cloud/) {
            print $r_fp $vars{$file}, " = paste(cloud.dir, ", $vars{$file},
                ", sep = \"/\")\n";
        }
        elsif($file =~ /^table-/) {
            print $r_fp $vars{$file}, " = paste(tex.dir, ", $vars{$file},
                ", sep = \"/\")\n";
        }
        else {
            print $r_fp $vars{$file}, " = paste(output.dir, ", $vars{$file},
                ", sep = \"/\")\n";
        }
    }
    foreach my $pdf (@pdf_list) {
        print $r_fp $vars{$pdf}, " = paste(pdf.dir, ", $vars{$pdf}, ", sep = \"/\")\n";
    }

    print $r_fp "par(cex = text.size)\n";
}

################################################################################
#                                                                              #
#  ####  ###  #   # #   # ##### #   #       ####  #      ###  #####            #
# #     #   # ##  # #  #  #      # #        #   # #     #   #   #              #
#  ###  ##### # # # ###   ####    #         ####  #     #   #   #              #
#     # #   # #  ## #  #  #       #         #     #     #   #   #              #
# ####  #   # #   # #   # #####   #         #     #####  ###    #              #
#                                     #####                                    #
#                                                                              #
################################################################################

sub sankey_plot {
    my ($r_fp, $filevar, $links, $palvar) = @_;

    warn "Cannot write a sankey plot to $filevar as R connection not open\n" if !defined($r_fp);

    my %nodes;
    foreach my $link (keys(%$links)) {
        $nodes{$link}++;
        foreach my $link_end (keys(%{$$links{$link}})) {
            $nodes{$link_end}++;
        }
    }

    my @sort_nodes = sort {$a cmp $b} keys(%nodes);

    if(scalar(@sort_nodes) == 0) {
        warn "No nodes found for Sankey plot to file $filevar\n";
        return;
    }

    for(my $i = 0; $i <= $#sort_nodes; $i++) {
        $nodes{$sort_nodes[$i]} = $i;
    }
    my $node_str = "\"".join("\", \"", @sort_nodes)."\"";

    my @sources;
    my @targets;
    my @values;

    foreach my $src (keys(%$links)) {
        foreach my $targ (keys(%{$$links{$src}})) {
            my $val = $links->{$src}->{$targ};

            push(@sources, $nodes{$src});
            push(@targets, $nodes{$targ});
            push(@values, $val);
        }
    }
    my $src_str = join(", ", @sources);
    my $targ_str = join(", ", @targets);
    my $val_str = join(", ", @values);

    my $palette_str = "JS(\"d3.scaleOrdinal(d3.schemeCategory10);\")";
    if(defined($palvar)) {
        $palette_str = "JS(paste0(\"d3.scaleOrdinal([\\\"\", ".
            "paste0(names($palvar), collapse = \"\\\", \\\"\"), ".
            "\"\\\"], [\\\"\", ".
            "paste0(unlist($palvar), collapse = \"\\\", \\\"\"), ".
            "\"\\\"]);\"))";
    }

    # This is based on code from https://www.geeksforgeeks.org/sankey-plot-in-r/
    # (Accessed 15 September 2024 from a sunny Cracow)

    print $r_fp "nodes <- data.frame(name = c($node_str))\n",
        "links <- data.frame(source = c($src_str),\n",
        "\ttarget = c($targ_str),\n",
        "\tvalue = c($val_str))\n",
        "sankeyPlotPapers <- sankeyNetwork(Links = links, Nodes = nodes,\n",
        "\tSource = \"source\", Target = \"target\",\n",
        "\tValue = \"value\", NodeID = \"name\",\n",
        "\tunits = \"n\", fontSize = sankey.fontsize,\n",
        "\tcolourScale = $palette_str,\n",
        "\tfontFamily = cloud.font.family,\n",
        "\tnodeWidth = sankey.barwidth)\n",
        "saveWidget(sankeyPlotPapers, file = $filevar)\n";
}

################################################################################
#                                                                              #
#  ####  ###  #   # #   # ##### #   #       ####   ###  #####  ###             #
# #     #   # ##  # #  #  #      # #        #   # #   #   #   #   #            #
#  ###  ##### # # # ###   ####    #         #   # #####   #   #####            #
#     # #   # #  ## #  #  #       #         #   # #   #   #   #   #            #
# ####  #   # #   # #   # #####   #         ####  #   #   #   #   #            #
#                                     #####                                    #
#                                                                              #
################################################################################

sub sankey_data {
    my ($links, $prefix_from, $prefix_to, @labels) = @_;

    foreach my $label (@labels) {
        $links->{"$prefix_from: $label"}->{"$prefix_to: $label"}++;
    }
}

################################################################################
#                                                                              #
# ####        ####  ####   ###  #   # #####       ##### #   # #   #  ####      #
# #   #       #   # #   #   #   ##  #   #         #     #   # ##  # #          #
# ####        ####  ####    #   # # #   #         ####  #   # # # # #          #
# #   #       #     #   #   #   #  ##   #         #     #   # #  ## #          #
# #   #       #     #   #  ###  #   #   #         #      ###  #   #  ####      #
#       #####                               #####                              #
#                                                                              #
################################################################################

sub r_print_func {
    my ($r_fp) = @_;

print $r_fp <<R_FUNC;

# Store default ('backup') margins and another to play with

margin.bk = par()\$mai
margin = par()\$mai

################################################################################
# Text label sizes for bar charts
#
# Calculate the cex parameters needed to fit all the labels for a bar plot
# and the margin size needed to accommodate the resulting labels. This assumes
# barplot() is being called with horiz = T and las = 1.
################################################################################

bar.txt.sizes <- function(names.arg, p.txt.space = 0.9, p.txt.width.max = 0.5,
    cex.max = par()\$cex, extra.space = 0.2)
{
    pltwh = par()\$pin
    min.w = p.txt.space * margin.bk[2]
    max.w = min.w + p.txt.space * (p.txt.width.max * pltwh[1])
    max.h = (p.txt.space * pltwh[2]) / length(names.arg)
    txt.h = par()\$cin[2]
    
    # This is the height we need to use to fit the text for each bar on the axis
    txt.cex = max.h / txt.h
    if(!is.na(cex.max) && txt.cex > cex.max) {
        txt.cex = cex.max
    }

    # Now handle the width
    txt.w = max(strwidth(names.arg, cex = txt.cex, units = "inches",
        vfont = c("sans serif", "plain")))

    if(txt.w + extra.space <= min.w) {
        # Height needed for each bar allows us to fit bar names in margin

        return(list(max.cex = txt.cex, mai2 = margin.bk[2]))
    } else if(txt.w <= max.w) {
        # Need to expand the margin to fit the bar names

        return(list(max.cex = txt.cex, mai2 = extra.space + (txt.w / p.txt.space)))
    } else {
        # Need to shrink the text further to fit the maximum width

        txt.cex = txt.cex * (max.w / txt.w)
        return(list(max.cex = txt.cex, mai2 = margin.bk[2] + (p.txt.width.max * pltwh[1])))
    }
}

bar.txt.wh <- function(names.arg, p.txt.space = 0.9, p.txt.width.max = 0.5,
    width.min = 5, height.min = 5, extra.width = 0.2, extra.height = 0.2)
{
    txt.w = max(strwidth(names.arg, cex = par()\$cex, units = "inches",
        vfont = c("sans serif", "plain")))
    txt.h = par()\$cin[2] * length(names.arg)
    paper.w = ((txt.w / p.txt.space) / p.txt.width.max) + margin.bk[2] + margin.bk[4] + extra.width
    if(paper.w < width.min) {
        paper.w = width.min
    }
    paper.h = (txt.h / p.txt.space) + margin.bk[1] + margin.bk[3] + extra.height
    if(paper.h < height.min) {
        paper.h = height.min
    }
    left.margin = extra.width + (txt.w / p.txt.space)
    return(list(width = paper.w, height = paper.h, mai2 = left.margin))
}

################################################################################
# Confusion Matrix
#
# Extracted function from mutual_information() see comments there
################################################################################

confusion_matrix <- function(x, y) {
    stopifnot(length(x) == length(y))
    stopifnot(all(is.logical(x)))
    stopifnot(all(is.logical(y)))

    n = length(x)

    xx = ifelse(x, 2, 1)
    yy = ifelse(y, 2, 1)

    M = matrix(0, nrow = 2, ncol = 2)
    for(i in 1:n) {
        M[xx[i], yy[i]] = M[xx[i], yy[i]] + 1
    }

    return(M)
}

################################################################################
# Mutual Information
#
# See https://en.wikipedia.org/wiki/Mutual_information
#
# N.B. The basics of this function were produced by Chat-GPT on 17 April 2025.
# Wikipedia entries indicated were checked against code. Main differences --
# largely to improve clarity.
#
#   + Confirm that x and y are arrays of logicals
#   + Calculate xx and yy so that it is not necessary to add 1 to them when
#     using them as indexes to M
#   + Extract confusion_matrix() so it can be used elsewhere
################################################################################

mutual_information <- function(x, y) {
    stopifnot(length(x) == length(y))
    stopifnot(all(is.logical(x)))
    stopifnot(all(is.logical(y)))

    n = length(x)

    M = confusion_matrix(x, y)

    # Convert to probabilities
    M = M / n

    # Marginal probabilities -- see https://en.wikipedia.org/wiki/Marginal_distribution
    px = rowSums(M)
    py = colSums(M)

    # Calculate mutual information
    mi = 0
    for(i in 1:2) {
        for(j in 1:2) {
            pxy = M[i, j]
            if(pxy > 0) {
                mi = mi + (pxy * log2(pxy / (px[i] * py[j])))
            }
        }
    }
    return(mi)
}

################################################################################
# LaTeX Table
#
# Convert a Data Frame to some copy/pastable LaTeX containing the data
################################################################################

latex_table <- function(df, caption = "Table caption", label = "tab:label", dig = 3,
    file = NA, jasss = (table.format == "JASSS"), lncs = (table.format == "LNCS"),
    transpose = FALSE, row.totals = FALSE, col.totals = FALSE, bars = NA,
    HPC.table = FALSE, na.txt = " ", small = FALSE, pct = c())
{
    if(!is.na(file)) {
        logbook("Writing table \\"", label, "\\" to file \\"", file, "\\"")
        sink(file)
    }
    if(!is.na(bars)) {
        cat("% Code for preamble from https://github.com/jirispilka/latex-tikz-table\\n")
        cat("%\\\\newcommand{\\\\drawbox}[2]{\\n")
        cat("%    \\\\begin{tikzpicture}\\n")
        cat("%        \\\\def\\\\w{2} % width of a box\\n")
        cat("%        \\\\def\\\\x{\\\\w * #1 / #2}\\n")
        if(jasss) {
            cat("%        \\\\filldraw[fill = JASSScolor, draw = white] (0, 0) rectangle (\\\\x, 0.2);\\n")
        }
        else {
            cat("%        \\\\filldraw[fill = gray, draw = white] (0, 0) rectangle (\\\\x, 0.2);\\n")
        }
        cat("%    \\\\end{tikzpicture}\\n")
        cat("%}\\n")
    }
    if(transpose) {
        dft = data.table::transpose(df)
        names(dft) = row.names(df)
        row.names(dft) = names(df)
        df = dft
    }
    dig.bk = unlist(options("digits"))
    options(digits = dig)
    cat("\\\\begin{table}")
    if(jasss) {
        cat("[ht!]\\n")
    }
    else {
        cat("\\n\\\\caption{", caption, "}\\n", sep = "")
    }
    cat("\\\\centering\\n")

    has.rowlab = any(grep("\\\\D", row.names(df), perl = TRUE))
    numeric.col = sapply(df, is.numeric)
    boolean.col = sapply(df, is.logical)
    colty = ifelse(numeric.col, "r", ifelse(boolean.col, "c", "l"))
    if(row.totals) {
        colty = c(colty, "r")
    }
    if(!is.na(bars)) {
        colty = c(colty, "l")
    }
    rown = gsub("&", "\\\\&", row.names(df), fixed = TRUE)

    cat("    \\\\begin{tabular}{")
    if(lncs) {
        cat("|")
    }
    if(has.rowlab) {
        cat("l")
        if(lncs) {
            cat("|")
        }
    }
    if(jasss) {
        cat(paste(colty, collapse = ""))
    } else {
        cat(paste(colty, collapse = "|"))
        cat("|")
    }
    cat("}\\n")
    if(jasss) {
        cat("\\\\toprule\\n")
    } else {
        cat("\\\\hline\\n")
    }
    if(HPC.table) {
        cline.start = 1
        cline.end = 4
        if(has.rowlab) {
            cat(" & ")
            cline.start = 2
            cline.end = 5
        }
        cat("\\\\multicolumn{4}{c}{HPC?}")
        if(row.totals) {
            cat(" & ")
        }
        cat("\\\\\\\\\\n")
        if(has.rowlab || row.totals) {
            cat("\\\\cline{", cline.start, "-", cline.end, "}\\n", sep = "")
        }
        else {
            cat("\\\\hline\\n")
        }
    }
    if(has.rowlab) {
        cat(" & ")
    }
    cat(paste(gsub("&", "\\\\&", names(df), fixed = TRUE), collapse = " & "))
    if(row.totals) {
        cat(" & Total")
    }
    cat(" \\\\\\\\\\n")
    if(jasss) {
        cat("\\\\midrule\\n")
    } else {
        cat("\\\\hline\\n")
    }
    for(r in 1:nrow(df)) {
        total.row = 0
        if(has.rowlab) {
            if(small) cat("\\\\small{")
            cat(rown[r])
            if(small) cat("}")
            cat(" & ")
        }
        for(c in 1:ncol(df)) {
            if(small) cat("\\\\small{")
            if(is.na(df[r, c])) {
                cat(na.txt)
            }
            else if(colty[c] == "l") {
                cat(gsub("&", "\\\\&", df[r, c], fixed = TRUE))
            }
            else if(colty[c] == "c") {
                if(df[r, c] == TRUE) {
                    cat("\$\\\\bullet\$")
                }
                else {
                    cat("\$\\\\circ\$")
                }
            }
            else {
                if(c \%in\% pct || names(df)[c] \%in\% pct) {
                    if(is.numeric(df[r, c])) {
                        cat(round(100 * df[r, c]), "\\\\%", sep = "")
                    }
                    else {
                        cat(df[r, c])
                    }
                }
                else {
                    cat(df[r, c])
                    if(is.numeric(df[r, c])) {
                        total.row = total.row + df[r, c]
                    }
                }
            }
            if(small) cat("}")
            if(c < ncol(df)) {
                cat(" & ")
            }
        }
        if(row.totals) {
            cat(" & ")
            if(small) cat("\\\\small{")
            cat(total.row)
            if(small) cat("}")
        }
        if(!is.na(bars)) {
            cat(" & \\\\drawbox{", total.row, "}{", bars, "}")
        }
        cat(" \\\\\\\\\\n")
    }
    if(col.totals) {
        if(jasss) {
            cat("\\\\midrule\\n")
        }
        else {
            cat("\\\\hline\\n")
        }
        if(has.rowlab) {
            cat("TOTAL & ")
        }
        total.row = 0
        for(c in 1:ncol(df)) {
            if(colty[c] == "r" && !(c \%in\% pct || names(df)[c] \%in\% pct)) {
                total.col = sum(df[, c], na.rm = TRUE)
                if(is.numeric(total.col)) {
                    total.row = total.row + total.col
                    cat(total.col)   
                }
            }
            if(c < ncol(df)) {
                cat(" & ")
            }
        }
        if(row.totals) {
            cat(" & ", total.row)
        }
        if(!is.na(bars)) {
            cat(" & ")
        }
        cat(" \\\\\\\\\\n")
    }
    if(jasss) {
        cat("\\\\bottomrule\\n")
    } else {
        cat("\\\\hline\\n")
    }
    cat("    \\\\end{tabular}\\n")
    if(jasss) {
        cat("\\\\caption{", caption, "}\\n", sep = "")
    }
    cat("    \\\\label{", label, "}\\n", sep = "")
    cat("\\\\end{table}\\n")
    if(!is.na(file)) {
        sink()
    }
    options(digits = dig.bk)
}

################################################################################
# Mutual Information Table
#
# Provide a table of mutual informations including the confusion matrix
# Might as well do the barchart while we are at it
################################################################################

mint <- function(df, base, cmp, caption, label, barlab, file = NA) {
    mi <- as.data.frame(matrix(NA, nrow = length(cmp), ncol = 9))
    row.names(mi) = cmp
    names(mi) = c("\\\\textbf{F}F", "\\\\textbf{F}T", "\\\\textbf{T}F",
        "\\\\textbf{T}T", "\$n\$\\\\textbf{T}", "\$n\$T",
        "\$\\\\hat{a}\$", "\$\\\\hat{b}\$", "\$I\$")
    n = nrow(df)

    for(r in 1:length(cmp)) {
        M = confusion_matrix(df[, base], df[, cmp[r]])
        I = mutual_information(df[, base], df[, cmp[r]])
        mi[r, 1] = M[1, 1]
        mi[r, 2] = M[1, 2]
        mi[r, 3] = M[2, 1]
        mi[r, 4] = M[2, 2]
        mi[r, 5] = M[2, 1] + M[2, 2]
        mi[r, 6] = M[1, 2] + M[2, 2]
        P = M / n
        mi[r, 7] = (P[1, 2] + P[2, 1]) / 2
        mi[r, 8] = (P[2, 2] - P[1, 1]) / (P[1, 1] + P[2, 2])
        mi[r, 9] = I
    }

    latex_table(mi, caption, label, file = file)
    txtsz = bar.txt.sizes(cmp)
    margin[2] = txtsz\$mai2
    par(mai = margin)
    barplot(mi\$\`\$I\$\`, horiz = T, las = 1, xlim = c(0, 1), xlab = barlab,
        names.arg = cmp, cex.names = txtsz\$max.cex, border = NA)
    margin[2] = margin.bk[2]
    par(mai = margin.bk)
}

################################################################################
# Nested barplot with error bars
#
# Plot a set of headings of a dataframe in a series of barplots of increasingly
# light shades. If a heading has another column with '.err' appended to its name
# treat these as 'whiskers' on each bar to reflect any uncertainty
################################################################################

berrplot <- function(df, headings, title, proportions = FALSE, shrink = 0.67,
    err.lwd = 2, cex.names = 0.33, max.factor = 1.2, pal = grey.colors(length(headings)))
{
    h.col = rep(NA, length(headings))
    h.err = rep(NA, length(headings))
    h.max = 0
    if(length(pal) < length(headings)) {
        stop("Provided palette has length ", length(pal), " -- which is insufficient for ",
            length(headings), " headings", call. = FALSE)
    }
    h.clr = pal[1:length(headings)]
    for(i in 1:length(headings)) {
        if(headings[i] \%in\% names(df)) {
            h.col[i] = which(names(df) == headings[i])
            h.max = max(c(h.max, df[, h.col[i]]), na.rm = TRUE)
            err.name = paste0(headings[i], ".err")
            if(err.name \%in\% names(df)) {
                h.err[i] = which(names(df) == err.name)
                h.max = max(c(h.max, df[, h.col[i]] + df[, h.err[i]]), na.rm = TRUE)
            }
        } else {
            stop(headings[i], " is not one of ", paste0(names(df), collapse = ", "), call. = FALSE)
        }
    }
    h.max = max.factor * h.max
    if(proportions) h.max = 1

    txtsz = bar.txt.sizes(row.names(df))
    if(txtsz\$max.cex < 1) {
        err.lwd = err.lwd / 2
    }

    tots = rep(1, nrow(df))
    if(proportions) {
        tots = df[, h.col[1]]
        if(!is.na(h.err[1])) {
            tots = tots + df[, h.err[1]]
        }
    }

    margin[2] = txtsz\$mai2
    par(mai = margin)

    bp = barplot(df[, h.col[1]] / tots, horiz = T, las = 1, xlim = c(0, h.max),
        cex.names = txtsz\$max.cex, names.arg = row.names(df), border = NA,
        col = h.clr[1], main = title)
    cur.wd = shrink
    if(!is.na(h.err[1])) {
        for(i in 1:length(bp)) {
            lines(c(df[i, h.col[1]], (df[i, h.col[1]] + df[i, h.err[1]])) / tots[i],
                c(bp[i], bp[i]), lwd = err.lwd, col = h.clr[1])
            lines(c(df[i, h.col[1]] + df[i, h.err[1]], df[i, h.col[1]] + df[i, h.err[1]]) / tots[i],
                c(bp[i] - (cur.wd / 2), bp[i] + (cur.wd / 2)), lwd = err.lwd, col = h.clr[1])
        }
    }

    for(j in 2:length(h.col)) {
        rect(rep(0, length(bp)), bp - (cur.wd / 2), df[, h.col[j]] / tots, bp + (cur.wd / 2),
            col = h.clr[j], border = NA)
        cur.wd = cur.wd * shrink
        if(!is.na(h.err[j])) {
            for(i in 1:length(bp)) {
                if((df[i, h.col[j]] + df[i, h.err[j]]) > 0) {
                    lines(c(df[i, h.col[j]], df[i, h.col[j]] + df[i, h.err[j]]) / tots[i],
                        c(bp[i], bp[i]), lwd = err.lwd, col = h.clr[j])
                    lines(c(df[i, h.col[j]] + df[i, h.err[j]], df[i, h.col[j]] + df[i, h.err[j]]) / tots[i],
                        c(bp[i] - (cur.wd / 2), bp[i] + (cur.wd / 2)), lwd = err.lwd, 
                        col = h.clr[j])
                }
            }
        }
    }

    margin[2] = margin.bk[2]
    par(mai = margin.bk)
}

################################################################################
# Print a horizontal bar chart to a PDF file, choosing the paper size
# appropriately
################################################################################

horiz.bar.pdf <- function(pdf.file, data, names, off = TRUE, ...) {
    sizes = bar.txt.wh(names)
    pdf(pdf.file, width = sizes\$width, height = sizes\$height)
    margin[2] = sizes\$mai2
    par(mai = margin)
    bp = barplot(data, names.arg = names, horiz = TRUE, las = 1, border = NA, ...)
    if(off) {
        dev.off()
    }
    margin[2] = margin.bk[2]
    par(mai = margin.bk)
    return(bp)
}

################################################################################
# Print a vertical bar chart to a PDF file
################################################################################

vert.bar.pdf <- function(pdf.file, data, names, ...) {
    pdf(pdf.file)
    bp = barplot(data, names.arg = names, ...)
    dev.off()
    return(bp)
}

################################################################################
# Print a bar chart with error bars, choosing the paper size appropriately
################################################################################

berr.pdf <- function(pdf.file, data, headings, title, ...) {
    sizes = bar.txt.wh(names(data))
    pdf(pdf.file, width = sizes\$width, height = sizes\$height)
    berrplot(data, headings, title, ...)
    dev.off()
}

R_FUNC
}
