# Auto-generated WoS.pm
#
# Generated on 2024-03-11 16:06:04 by gary in /Users/gary/OneDrive - The James Hutton Institute/Active Projects/ExAMPLER-internal/SLR running:
# bin/interesting.pl "confusion.csv"
#
# To use, copy to WoS.pm and edit $THRESHOLD and %remove
#
# All scripts needing to know which Web of Science categories
# are 'in' should then `use WoS;`. This ensures consistency.
# Exported functions:
#
# threshold() -- returns $THRESHOLD
# is_definite(category) -- Boolean: is the Web of Science category 'in'?
# is_removed(category) -- Boolean: has the Web of Science category been removed?
# should_be_definite(category, n_comp_sci, n_soc_sci) -- Boolean: should the Web
#    of Science category be 'in' given the number of computing science papers
#    and number of social science papers found?

package WoS;

use Exporter;

@ISA = (Exporter);
@EXPORT = qw ( threshold, is_definite, is_removed, should_be_definite, all_definite, is_category, clean_category );

use strict;
use warnings;

# Human intervention: adjust $THRESHOLD in accordance with discussion --
# typically based on terminal output from bin/interesting.pl
# Choose a value that includes the highest ratio for a Web of Science
# category that is deemed to be in the social sciences.

# Human intervation -- Meeting on 11 March 2024 discussion with
# Alison Heppenstall, Doug Salt, Ric Colasanti, Richard Milton & Gary Polhill
our $THRESHOLD = 13.35; # Energy and Fuels taken as max wuth 13.34

my %categories = (
	'Instruments and Instrumentation' => 823,
	'Materials Science, Multidisciplinary' => 467,
	'Physics, Multidisciplinary' => 366,
	'Physics, Applied' => 180,
	'Engineering, Chemical' => 145,
	'Chemistry, Analytical' => 80.5,
	'Biochemical Research Methods' => 73.25,
	'Automation and Control Systems' => 70.3804347826087,
	'Neurosciences' => 53,
	'Engineering, Mechanical' => 51.7777777777778,
	'Mathematics, Applied' => 46.3448275862069,
	'Biology' => 42,
	'Mathematics' => 40.6666666666667,
	'Robotics' => 38.0512820512821,
	'Mathematical and Computational Biology' => 34.8846153846154,
	'Engineering, Multidisciplinary' => 34.375,
	'Engineering, Electrical and Electronic' => 30.6570247933884,
	'Medical Informatics' => 28.6,
	'Engineering, Biomedical' => 28.125,
	'Engineering, Marine' => 23,
	'Computer Science, Hardware and Architecture' => 22.6176470588235,
	'Telecommunications' => 19.8369565217391,
	'Computer Science, Cybernetics' => 17.5147058823529,
	'Computer Science, Theory and Methods' => 16.970479704797,
	'Physics, Mathematical' => 16.6470588235294,
	'Computer Science, Software Engineering' => 16.537037037037,
	'Mechanics' => 15.8235294117647,
	'Energy and Fuels' => 13.344262295082,
	'Computer Science, Artificial Intelligence' => 11.6152597402597,
	'Imaging Science and Photographic Technology' => 10.1666666666667,
	'Engineering, Geological' => 9,
	'Computer Science, Interdisciplinary Applications' => 8.35555555555556,
	'Health Care Sciences and Services' => 6.5,
	'Computer Science, Information Systems' => 5.8070652173913,
	'Mathematics, Interdisciplinary Applications' => 5.69856459330144,
	'Acoustics' => 5.5,
	'Engineering, Civil' => 4.59248554913295,
	'Logic' => 3.64285714285714,
	'Construction and Building Technology' => 3.47252747252747,
	'Engineering, Manufacturing' => 3.22147651006711,
	'Statistics and Probability' => 2.95744680851064,
	'Water Resources' => 2.80882352941176,
	'Operations Research and Management Science' => 2.6694648478489,
	'Plant Sciences' => 2.5,
	'Remote Sensing' => 2.43103448275862,
	'Transportation Science and Technology' => 2.30952380952381,
	'Engineering, Industrial' => 2.18722466960352,
	'behavioural Sciences' => 2.16666666666667,
	'Education, Scientific Disciplines' => 1.875,
	'Architecture' => 1.84615384615385,
	'Art' => 1.75,
	'Social Sciences, Mathematical Methods' => 1.66279069767442,
	'Ergonomics' => 1.56603773584906,
	'Transportation' => 1.5054347826087,
	'Music' => 1.5,
	'Nursing' => 1.5,
	'Engineering, Environmental' => 1.42541436464088,
	'Education and Educational Research' => 1.28723404255319,
	'Psychology, Experimental' => 1.16666666666667,
	'Green and Sustainable Science and Technology' => 1.16571428571429,
	'Environmental Sciences' => 1.12398921832884,
	'Social Sciences, Interdisciplinary' => 1.05666156202144,
	'Endocrinology and Metabolism' => 1,
	'Information Science and Library Science' => 0.983425414364641,
	'Psychology, Social' => 0.857142857142857,
	'Law' => 0.846153846153846,
	'Ecology' => 0.842857142857143,
	'Agriculture, Multidisciplinary' => 0.842105263157895,
	'Food Science and Technology' => 0.777777777777778,
	'Health Policy and Services' => 0.769230769230769,
	'Public, Environmental and Occupational Health' => 0.699346405228758,
	'Psychology, Mathematical' => 0.666666666666667,
	'Psychology, Applied' => 0.657894736842105,
	'Urban Studies' => 0.623188405797101,
	'Management' => 0.575601374570447,
	'Geography, Physical' => 0.527397260273973,
	'Multidisciplinary Sciences' => 0.522853957636566,
	'Geosciences, Multidisciplinary' => 0.514851485148515,
	'Spectroscopy' => 0.5,
	'Environmental Studies' => 0.472081218274112,
	'Communication' => 0.457142857142857,
	'Evolutionary Biology' => 0.454545454545455,
	'Forestry' => 0.444444444444444,
	'Economics' => 0.414549653579677,
	'Business' => 0.36144578313253,
	'Meteorology and Atmospheric Sciences' => 0.361111111111111,
	'Psychology, Multidisciplinary' => 0.358974358974359,
	'Criminology and Penology' => 0.333333333333333,
	'Business, Finance' => 0.271186440677966,
	'Medicine, General and Internal' => 0.25,
	'Biodiversity Conservation' => 0.25,
	'Social Issues' => 0.240740740740741,
	'Geography' => 0.226361031518625,
	'Linguistics' => 0.214285714285714,
	'Regional and Urban Planning' => 0.19921875,
	'Political Science' => 0.127906976744186,
	'Sociology' => 0.115107913669065,
	'Public Administration' => 0.101123595505618,
	'History and Philosophy Of Science' => 0.0909090909090909,
	'Ethics' => 0.0909090909090909,
	'Psychology' => 0.0833333333333333,
	'Philosophy' => 0.0416666666666667,
	'Development Studies' => 0.032258064516129,
	'Archaeology' => 0.0136986301369863
);

my %remove = (
    # Human intervention to insert removed categories here
    # Use $category => 1, for each category that is not 'definite'
	'Imaging Science and Photographic Technology' => 1,
	'Engineering, Geological' => 1,
	'Computer Science, Information Systems' => 1,
	'Mathematics, Interdisciplinary Applications' => 1,
	'Acoustics' => 1,
	'Logic' => 1,
	'Engineering, Manufacturing' => 1,
	'Statistics and Probability' => 1,
	'Plant Sciences' => 1,
	'Remote Sensing' => 1,
	'Engineering, Industrial' => 1,
	'Art' => 1,
	'Ergonomics' => 1,
	'Music' => 1,
	'Endocrinology and Metabolism' => 1,
	'Information Science and Library Science' => 1,
	'Ecology' => 1,
	'Food Science and Technology' => 1,
	'Geography, Physical' => 1,
	'Geosciences, Multidisciplinary' => 1,
	'Spectroscopy' => 1,
	'Evolutionary Biology' => 1,
	'Meteorology and Atmospheric Sciences' => 1,
	'Medicine, General and Internal' => 1,
	'Linguistics' => 1,
	'History and Philosophy Of Science' => 1,
	'Ethics' => 1,
	'Philosophy' => 1,
	'Archaeology' => 1
);

sub threshold {
    return $THRESHOLD;
}

sub clean_category {
	my ($cat) = @_;

	$cat =~ s/^\s+//;
	$cat =~ s/\s+$//;

	$cat = $1 if($cat =~ /^\"([^"]+)\"$/);

	return $cat;
}

sub is_category {
	my ($cat) = @_;

	return exists($categories{$cat});
}

sub is_definite {
    my ($cat, $warn_please) = @_;

	$cat = &clean_category($cat);

    if(!exists($categories{$cat})) {
        warn "Category \"$cat\" does not exist\n" if(defined($warn_please) && $warn_please);
        return 0;
    }

    return 0 if(&is_removed($cat));
    return ($categories{$cat} <= $THRESHOLD);
}

sub should_be_definite {
    my ($cat, $n_comput, $n_social) = @_;

	$cat = &clean_category($cat);

	return 0 if($n_social == 0);
    return 0 if($n_comput / $n_social > $THRESHOLD);
    return !&is_removed($cat);
}

sub is_removed {
    my ($cat) = @_;

	$cat = &clean_category($cat);

    return exists($remove{$cat});
}

sub all_definite {
    my @definite;

    foreach my $cat (sort { $a cmp $b } keys(%categories)) {
        push(@definite, $cat) if(&is_definite($cat));
    }

	return @definite;
}

1;
