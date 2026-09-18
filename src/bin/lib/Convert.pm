package Convert; 


our $LENGTH = 50;

use Exporter;

@ISA = (Exporter);
@EXPORT = qw(standardise_and_remove_unicode);

use strict;
use warnings;
use Text::Unidecode;

sub remove_unicode {
    
    my $text = unidecode($_[0]);

    # Unicode (I think?) corrections. I will apply these when I convert from
    # bib

    $text =~ s/\xe2\x80\x9c/\"/g; # Open double apostrophe
    $text =~ s/\xe2\x80\x9d/\"/g; # Close double apostrophe
    $text =~ s/\xe2\x80\x98/\'/g; # Open single apostrophe
    $text =~ s/\xe2\x80\x99/\'/g; # Close single apostrophe
    $text =~ s/\xe2\x88\x97/\*/g; # Asterisk
    $text =~ s/\xe2\x80\xb2//g; # Back tick
    $text =~ s/\xe2\x88\x9e/infinity/g; # Infinity sign
    $text =~ s/\xe2\x88\x92/\-/g; # - sign
    $text =~ s/\xe2\x80\x90/\-/g; # Short dash
    $text =~ s/\xe2\x80\x91/\-/g; # ? dash
    $text =~ s/\xe2\x80\x92/\-/g; # ? dash
    $text =~ s/\xe2\x80\x93/\-/g; # Long dash
    $text =~ s/\xe2\x80\x94/\-/g; # Medium dash
    $text =~ s/\xef\xbc\x91/\:/g; # Colon
    $text =~ s/\xef\xbc\x9a/\:/g; # Colon
    $text =~ s/\xef\xbf\xbd/\a/g; # a
    $text =~ s/\xc2\xa0/ /g; # No breaking space
    $text =~ s/\xc2\xae/(r)/g; # registered trade mark
    $text =~ s/\xc3\xa0/a/g; # a with ` above it.
    $text =~ s/\xc3\xa3/a/g; # a with ~ above it.
    $text =~ s/\xc3\xa9/e/g; # e with ' above it.
    $text =~ s/\xc3\xa1/a/g; # a with ' above it.
    $text =~ s/\xc3\xa2/a/g; # a circumflex
    $text =~ s/\xc3\xa7/c/g; # c with 5 below it.
    $text =~ s/\xc3\xaf/i/g; # i with umlaut above it.
    $text =~ s/\xc3\xad/i/g; # i with ' above it.
    $text =~ s/\xc3\xb1/n/g; # n with ~ above it.
    $text =~ s/\xc3\xb4/o/g; # a with ^ above it.
    $text =~ s/\xc3\x85/angstrom/g; # A with o above it.
    $text =~ s/\xc4\x8c/C/g; # C with u above it.
    $text =~ s/\xc5\xbd/Z/g; # Z with u above it.
    $text =~ s/\xce\xb1/alpha/g; # Alpha U+03B1
    $text =~ s/\xce\xb2/beta/g; # Beta
    $text =~ s/\xce\xb3/gamma/g; # Gamma
    $text =~ s/\xce\xb4/delta/g; # Delta
    $text =~ s/\xce\xba/kappa/g; # Kappa
    $text =~ s/\xce\xbb/lambda/g; # Lambda
    $text =~ s/\xce\xbc/mu/g; # Mu 131
    $text =~ s/\x7c\x7c/parallel/g; # ||
 
    # Latex forms - I will apply these when I do the conversion from bib to csv
    # as well. 

    $text =~ s/\`\`/\"/g;
    $text =~ s/\'\'/\"/g;
    $text =~ s/\`/\'/g;


   return $text;
   
}    

sub spelling_errors {

    my $text = $_[0];
   
    # Text corrections for titles only - these are well dodgy
    $text =~ s/^50th Anniversary invited article//;
    $text =~ s/^Article //;
    $text =~ s/^Author correction: //i;
    $text =~ s/^Brief paper //i;
    $text =~ s/^CLINICAL INVESTIGATION //;
    $text =~ s/^Chapter [0-9]: //;
    $text =~ s/^Correction to:? //;
    $text =~ s/^Correction: qq//;
    $text =~ s/^Correction: //;
    $text =~ s/^Corrigendum to //;
    $text =~ s/^Corrigendum to: //;
    $text =~ s/^Corrigendum: //;
    $text =~ s/^Editorial: //;
    $text =~ s/^Erratum: //;
    $text =~ s/^Erratum to \'?//;
    $text =~ s/^Notice of Retraction: //;
    $text =~ s/^Original Article: //;
    $text =~ s/^Original publication //;
    $text =~ s/^RETRACTED: //;
    $text =~ s/^RETRACTED ARTICLE: //;
    $text =~ s/^Retraction notice to//;
    $text =~ s/^MRSAT/MRSA/;
    $text =~ s/^\"Silent/Silent/;
    $text =~ s/acquistion/acquisition/ig;
    $text =~ s/Careara/Carcara/g;
    $text =~ s/validatlion/validation/g;
    $text =~ s/reeonfigurable/reconfigurable/g;
    $text =~ s/traffc/Traffic/g;
    $text =~ s/Microsiulation/Microsimulation/g;
    $text =~ s/mflitary/military/g;
    $text =~ s/muiti/multi/g;
    $text =~ s/multiarvent/multiagent/g;
    $text =~ s/racinguWhen/racing when/g;
    $text =~ s/Lagranglan/Lagrangian/g;
    $text =~ s/proceb:/process:/g;
    $text =~ s/Undestanding/Understanding/g;
    $text =~ s/H Ants/Ants/g;
    $text =~ s/Human cask/Human task/g;
    $text =~ s/rnultiscale/multiscale/g;
    $text =~ s/enviroment/enjvironment/g;
    $text =~ s/fonnation/formation/g;
    $text =~ s/Caonspecific/Conspecific/g;
    $text =~ s/tab es/tables/g;
    $text =~ s/beneft/benefit/g;
    $text =~ s/TTTowards/Towards/g;
    $text =~ s/Agent\-ased/Agent-based/g;
    $text =~ s/io a heterogeneous/in a heterogeneous/;
    $text =~ s/^ Odeling /Modelling /;
    $text =~ s/phase IfsI /phase II /;
    $text =~ s/Tralisportation/Transportation/g;
    $text =~ s/Q-Leaning/Q-Learning/g;
    $text =~ s/enjvironment/environment/g;
    $text =~ s/pumpec/Pumped/g;
    $text =~ s/SSimulations/Simulations/g;
    $text =~ s/1ollective/Collective/g;
    $text =~ s/atomatic/automatic/g;
    $text =~ s/autonomie/autonomic/g;
    $text =~ s/behaviou?rm1/behaviour/g;
    $text =~ s/^d The/The/g;
    $text =~ s/Anontological/An ontological/g;
    $text =~ s/Erds-Renyi/Erdos-Renyi/g;
    $text =~ s/demorgraphic/demographic/g;
    $text =~ s/byconversion/bioconversion/g;
    $text =~ s/tariff/tarrif/g;
    $text =~ s/ion off a/ion of a/g;
    $text =~ s/l o\. The/l of the/g;
    $text =~ s/vis-.-vis/vis-a-vis/g;
    $text =~ s/na.ve/naive/g;
    $text =~ s/^ya..a:/yaparallel to a/;
    $text =~ s/^\"A/A/;
    $text =~ s/neighborhoods...?neighborhoods/neighborhoods-neighborhoods/g;
    $text =~ s/^-SMASH/Q-SMASH/;
    $text =~ s/rnicrosimulation/microsimulation/gi;

     # Standardise forms . I will apply these when I convert from bib.

    $text =~ s/behavior/behaviour/ig;
    $text =~ s/modeling/modelling/ig;
    $text =~ s/withholding/witholding/ig;
    $text =~ s/labor/labour/ig;
    $text =~ s/center/centre/ig;

    $text =~ s/\&/and/g;
    $text =~ s/1st/first/gi;
    $text =~ s/\+/plus/g;
    $text =~ s/ of of/ of/ig;
    
    return $text
}

;

