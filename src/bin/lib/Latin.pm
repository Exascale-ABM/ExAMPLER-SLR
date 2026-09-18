package Latin;

# Why not use Unicode::CharNames, I hear you ask?
# Because it doesn't compile on a Mac.
# I hate packages. And accented Latin characters.
# I _really_ hate them.

use Exporter;

@ISA = (Exporter);
@EXPORT = qw(init, no_accents, atoz, has_accent, encode_latex, decode_latex, serialize);

use strict;
use warnings;
use utf8;
use charnames ();

my %names;
my %code_points;
my %latex_encode;
my %latex_decode;
my @latex_cmd;
my $initialized = 0;

##############################################################################
#
#   ###  #   #  ###  #####
#    #   ##  #   #     #  
#    #   # # #   #     #  
#    #   #  ##   #     #  
#   ###  #   #  ###    #  
#                         
##############################################################################

sub init {
    my @letters = (
        "A", "AFRICAN D", "ALPHA", "AE", "B", "BLACKLETTER E", "BLACKLETTER O",
        "C", "D", "E", "ENG", "ESH", "ETH", "EZH", "F",
        "G", "GAMMA", "GLOTTAL STOP", "H", "HALF H", "HV", "HWAIR", "I", "IOTA",
        "J", "K", "L", "LAMBDA", "LONG S", "M",
        "N", "O", "OI", "OPEN E", "OPEN O", "OU", "P", "Q", "R",
        "S", "SCHWA", "SHARP S", "SMALL Q",
        "T", "TAILLESS PHI", "THORN", "TONE FIVE", "TONE SIX", "TONE TWO",
        "TURNED A", "TURNED ALPHA", "TURNED DELTA", "TURNED M",
        "TURNED R", "TURNED V", "U", "UO", "UPSILON", "V", "W", "WYNN", "X", "Y",
        "YOGH", "Z"
    );

    my %latex_letters = (
        "A" => ["A", "a"],
        "A WITH RING" => ["\\AA", "\\aa"],
        "AE" => ["\\AE", "\\ae"],
        "B" => ["B", "b"],
        "C" => ["C", "c"],
        "D" => ["D", "d"],
        "D WITH STROKE" => ["\\DJ", "\\dj"],
        "E" => ["E", "e"],
        "ENG" => ["\\NG", "\\ng"],
        "ETH" => ["\\DH", "\\dh"],
        "F" => ["F", "f"],
        "G" => ["G", "g"],
        "H" => ["H", "h"],
        "I" => ["I", "i"],
        "J" => ["J", "j"],
        "K" => ["K", "k"],
        "L" => ["L", "l"],
        "L WITH STROKE" => ["\\L", "\\l"],
        "M" => ["M", "m"],
        "N" => ["N", "n"],
        "O" => ["O", "o"],
        "U WITH HORN" => ["\\OHORN", "\\ohorn"],
        "O WITH STROKE" => ["\\O", "\\o"],
        "P" => ["P", "p"],
        "Q" => ["Q", "q"],
        "R" => ["R", "r"],
        "S" => ["S", "s"],
        "SHARP S" => ["\\SS", "\\ss"],
        "T" => ["T", "t"],
        "THORN" => ["\\TH", "\\th"],
        "U" => ["U", "u"],
        "U WITH HORN" => ["\\UHORN", "\\uhorn"],
        "V" => ["V", "v"],
        "W" => ["W", "w"],
        "X" => ["X", "x"],
        "Y" => ["Y", "y"],
        "Z" => ["Z", "z"]
    );

    my %latex_accents = (
        "ACUTE" => ["\\\'{", "}"],
        "BAR" => ["\\b{", "}"],
        "BREVE" => ["\\u{", "}"],
        "CARON" => ["\\v{", "}"],
        "CEDILLA" => ["\\c{", "}"],
        "CIRCUMFLEX" => ["\\^{", "}"],
        "DIARESIS" => ["\\\"{", "}"],
        "DOT ABOVE" => ["\\.{", "}"],
        "DOT BELOW" => ["\\d{", "}"],
        "DOUBLE ACUTE" => ["\\H{", "}"],
        "DOUBLE GRAVE" => ["\\G{", "}"],
        "GRAVE" => ["\\`{", "}"],
        "MACRON" => ["\\={", "}"],
        "ONOGEK" => ["\\k{", "}"],
        "RING ABOVE" => ["\\r{", "}"],
        "TILDE" => ["\\~{", "}"],
    );

    my @cases = ("CAPITAL", "SMALL");

    # A programmer's curse on ALL accents!
    my @accents = ("ACUTE",
        "BAR",
        "BREVE", "BREVE AND ACUTE", "BREVE AND DOT BELOW", 
        "BREVE AND GRAVE", "BREVE AND HOOK ABOVE", "BREVE AND TILDE",
        "BREVE BELOW",
        "CARON", "CARON AND DOT ABOVE",
        "CEDILLA", "CEDILLA AND ACUTE", "CEDILLA AND BREVE",
        "CIRCUMFLEX", "CIRCUMFLEX AND ACUTE", "CIRCUMFLEX AND DOT BELOW",
        "CIRCUMFLEX AND GRAVE", "CIRCUMFLEX AND HOOK ABOVE", "CIRCUMFLEX AND TILDE",
        "CIRCUMFLEX BELOW",
        "COMMA BELOW",
        "CURL",
        "DESCENDER",
        "DIAERESIS", "DIAERESIS AND ACUTE", "DIAERESIS AND CARON", "DIAERESIS AND GRAVE",
        "DIAERESIS AND MACRON", "DIAERESIS BELOW",
        "DIAGONAL STROKE",
        "DOT ABOVE", "DOT ABOVE AND MACRON",
        "DOT BELOW", "DOT BELOW AND MACRON", "DOT BELOW AND DOT ABOVE",
        "DOUBLE ACUTE",
        "DOUBLE BAR",
        "DOUBLE GRAVE",
        "DOUBLE MIDDLE TILDE",
        "FLOURISH",
        "GRAVE",
        "HOOK", "HOOK ABOVE", "HOOK TAIL",
        "HORN", "HORN AND ACUTE", "HORN AND DOT BELOW", "HORN AND GRAVE",
        "HORN AND HOOK ABOVE", "HORN AND TILDE",
        "INVERTED BREVE",
        "LEFT HOOK",
        "LINE BELOW",
        "LONG RIGHT LEG",
        "LOW RING INSIDE",
        "MACRON", "MACRON AND ACUTE", "MACRON AND DIAERESIS", "MACRON AND GRAVE",
        "MIDDLE DOT",
        "MIDDLE RING",
        "MIDDLE TILDE",
        "NOTCH",
        "OGONEK", "OGONEK AND MACRON",
        "PALATAL HOOK",
        "RETROFLEX HOOK",
        "RIGHT HOOK",
        "RING ABOVE", "RING ABOVE AND ACUTE",
        "SHORT RIGHT LEG",
        "STROKE", "STROKE AND ACUTE",
        "SWASH TAIL",
        "TAIL",
        "TILDE", "TILDE AND ACUTE", "TILDE AND MACRON", "TILDE BELOW",
        "TOPBAR"
    );

    foreach my $letter (@letters) {
        for(my $i = 0; $i <= $#cases; $i++) {
            my $case = $cases[$i];
            my $name = "LATIN $case LETTER $letter";
            my $code_point = &charnames::string_vianame($name);
            if(defined($code_point)) {
                $names{$code_point} = $name;
                $code_points{$name} = $code_point;
                if(exists($latex_letters{$letter})) {
                    $latex_encode{$code_point} = $latex_letters{$letter}->[$i];
                    $latex_decode{$latex_letters{$letter}->[$i]} = $code_point;
                }
            }
            foreach my $accent (@accents) {
                $name = "LATIN $case LETTER $letter WITH $accent";
                $code_point = &charnames::string_vianame($name);
                if(defined($code_point)) {
                    $names{$code_point} = $name;
                    $code_points{$name} = $code_point;

                    if(exists($latex_letters{"$letter WITH $accent"})) {
                        my $encoding = $latex_letters{"$letter WITH $accent"}->[$i];
                        $latex_encode{$code_point} = $encoding;
                        $latex_decode{$encoding} = $code_point;
                        push(@latex_cmd, $encoding) if($encoding =~ /^\\/);
                    }
                    elsif(
                        exists($latex_letters{$letter})
                        && exists($latex_accents{$accent})
                    ) {
                        my $encoding = (
                            ($latex_accents{$accent}->[0])
                            .($latex_letters{$letter}->[$i])
                            .($latex_accents{$accent}->[1])
                        );
                        $latex_encode{$code_point} = $encoding;
                        $latex_decode{$encoding} = $code_point;
                        push(@latex_cmd, $encoding) if($encoding =~ /^\\/);
                    }
                }
            }
        }
    }
    $initialized = 1;
}

##############################################################################
#
#  #   #  ###         ###   ####  #### ##### #   # #####  ####
#  ##  # #   #       #   # #     #     #     ##  #   #   #    
#  # # # #   #       ##### #     #     ####  # # #   #    ### 
#  #  ## #   #       #   # #     #     #     #  ##   #       #
#  #   #  ###        #   #  ####  #### ##### #   #   #   #### 
#              #####                                          
#                                                             
##############################################################################

sub no_accents {
    my ($str) = @_;

    &init() if !$initialized;

    my $ret;

    foreach my $chr (split(//, $str)) {
        if(exists($names{$chr})) {
            my $name = $names{$chr};
            $name =~ s/ WITH .*$//;
            if(exists($code_points{$name})) {
                $ret .= $code_points{$name};
            }
            else {
                $ret .= "!";
            }
        }
        else {
            $ret .= "$chr";
        }
    }

    return $ret;
}

##############################################################################
#
#   ###  #####  ###  #####
#  #   #   #   #   #    # 
#  #####   #   #   #   #  
#  #   #   #   #   #  #   
#  #   #   #    ###  #####
#                         
##############################################################################

sub atoz {
    my ($str) = @_;

    &init() if !$initialized;

    my $ret;

    my %az = (
        "A" => ["A"], "AFRICAN D" => ["D"], "ALPHA" => ["A"],
        "AE" => ["A", "E"], "B" => ["B"], "BLACKLETTER E" => ["E"],
        "BLACKLETTER O" => ["O"],
        "C" => ["C"], "D" => ["D"], "E" => ["E"], "ENG" => ["N", "G"],
        "ESH" => ["S", "H"], "ETH" => ["T", "H"], "EZH" => ["Z", "H"],
        "F" => ["F"], "G" => ["G"], "GAMMA" => ["G"], "GLOTTAL STOP" => [],
        "H" => ["H"], "HALF H" => ["H"], "HV" => ["H", "V"], "HWAIR" => ["W", "H"],
        "I" => ["I"], "IOTA" => ["I"],
        "J" => ["J"], "K" => ["K"], "L" => ["L"], "LAMBDA" => ["L"],
        "LONG S" => ["S"], "M" => ["M"],
        "N" => ["N"], "O" => ["O"], "OI" => ["O", "I"], "OPEN E" => ["E"],
        "OPEN O" => ["O"], "OU" => ["O", "U"], "P" => ["P"], "Q" => ["Q"],
        "R" => ["R"], "S" => ["S"], "SCHWA" => ["E"], "SHARP S" => ["S", "S"],
        "SMALL Q" => ["Q"], "T" => ["T"], "TAILLESS PHI" => [], "THORN" => ["T", "H"],
        "TONE FIVE" => ["Q"], "TONE SIX" => ["H"], "TONE TWO" => ["E"],
        "TURNED A" => ["A"], "TURNED ALPHA" => ["A"], "TURNED DELTA" => ["D"],
        "TURNED M" => ["M"], "TURNED R" => ["R"], "TURNED V" => ["V"],
        "U" => ["U"], "UO" => ["U", "O"], "UPSILON" => ["U"], "V" => ["V"],
        "W" => ["W"], "WYNN" => ["W"], "X" => ["X"], "Y" => ["Y"],
        "YOGH" => ["G", "H"], "Z" => ["Z"],
    );

    foreach my $chr (split(//, $str)) {
        if(exists($names{$chr})) {
            my $name = $names{$chr};
            $name =~ s/ WITH .*$//;
            if(exists($code_points{$name})) {
                if($name =~ /^LATIN (.*) LETTER (.+)$/) {
                    my $case = $1;
                    my $letter = $2;

                    if(exists($az{$letter})) {
                        foreach my $azonly (@{$az{$letter}}) {
                            if(exists($code_points{"LATIN $case LETTER $azonly"})) {
                                $ret .= $code_points{"LATIN $case LETTER $azonly"};
                            }
                            else {
                                $ret .= "#";
                            }
                        }
                    }
                    else {
                        $ret .= "*";
                    }
                }
                else {
                    $ret .= "@";
                }
            }
            else {
                $ret .= "!";
            }
        }
        else {
            $ret .= "$chr";
        }
    }

    return $ret;
}

##############################################################################
#
#  #   #  ###   ####        ###   ####  #### ##### #   # #####
#  #   # #   # #           #   # #     #     #     ##  #   #  
#  ##### #####  ###        ##### #     #     ####  # # #   #  
#  #   # #   #     #       #   # #     #     #     #  ##   #  
#  #   # #   # ####        #   #  ####  #### ##### #   #   #  
#                    #####                                    
#                                                             
##############################################################################

sub has_accent {
    my ($str) = @_;

    &init() if !$initialized;

    foreach my $chr (split(//, $str)) {
        if(exists($names{$chr})) {
            if($names{$chr} =~ / WITH /) {
                return 1;
            }
        }
    }
    return 1;
}

##############################################################################
#
#  ##### #   #  ####  ###  ####  #####       #      ###  ##### ##### #   #
#  #     ##  # #     #   # #   # #           #     #   #   #   #      # # 
#  ####  # # # #     #   # #   # ####        #     #####   #   ####    #  
#  #     #  ## #     #   # #   # #           #     #   #   #   #      # # 
#  ##### #   #  ####  ###  ####  #####       ##### #   #   #   ##### #   #
#                                      #####                              
#                                                                         
##############################################################################

sub encode_latex {
    my ($str) = @_;

    &init() if !$initialized;

    my $latex = "";
    foreach my $chr (split(//, $str)) {
        if(exists($latex_encode{$chr})) {
            $latex .= $latex_encode{$chr};
        }
        else {
            $latex .= $chr;
        }
    }
    return $latex;
}

##############################################################################
#
#  ####  #####  ####  ###  ####  #####       #      ###  ##### ##### #   #
#  #   # #     #     #   # #   # #           #     #   #   #   #      # # 
#  #   # ####  #     #   # #   # ####        #     #####   #   ####    #  
#  #   # #     #     #   # #   # #           #     #   #   #   #      # # 
#  ####  #####  ####  ###  ####  #####       ##### #   #   #   ##### #   #
#                                      #####                              
#                                                                         
##############################################################################

sub decode_latex {
    my ($latex) = @;

    &init() if !$initialized;

    my $str = "";
    for(my $i = 0; $i < length($str); $i++) {
        my $chr = substr($latex, $i, 1);
        if($chr eq "\\") {
            my $found = 0;
            ENCODE_LOOP: foreach my $encoding (@latex_cmd) {
                my $n = length($encoding);
                if($i + $n <= length($str) && substr($latex, $i, $n) eq $encoding) {
                    $str .= $latex_decode{$encoding};
                    $i += $n;
                    $found = 1;
                    last ENCODE_LOOP;
                }
            }
            $str .= $chr if(!$found);
        }
        else {
            $str .= $chr;
        }
    }
    return $str;
}

##############################################################################
#
#   #### ##### ####   ###   ###  #      ###  ##### #####
#  #     #     #   #   #   #   # #       #      #  #    
#   ###  ####  ####    #   ##### #       #     #   #### 
#      # #     #   #   #   #   # #       #    #    #    
#  ####  ##### #   #  ###  #   # #####  ###  ##### #####
#                                                       
##############################################################################

sub serialize {
    &init() if !$initialized;

    foreach my $name (sort { $a cmp $b } keys(%code_points)) {
        print "$name: \"$code_points{$name}\"\n";
    }
}

1;