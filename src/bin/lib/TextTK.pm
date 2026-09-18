package TextTK;

use Exporter;

@ISA = (Exporter);
@EXPORT = qw(match_pct, n_words, match_words, match_len, first_eq_len,
    alns, azns, count_chrs);

use strict;
use warnings;
use Latin;

##############################################################################
# match_pct (str1, str2)
#
#  #   #  ###  #####  #### #   #       ####   #### #####
#  ## ## #   #   #   #     #   #       #   # #       #  
#  # # # #####   #   #     #####       ####  #       #  
#  #   # #   #   #   #     #   #       #     #       #  
#  #   # #   #   #    #### #   #       #      ####   #  
#                                #####                  
#                                                      
# What percentage of words are the same in the two strings?
##############################################################################

sub match_pct {
    my ($str1, $str2) = @_;

    $str1 = &azns($str1);
    $str2 = &azns($str2);

    my @words1 = split(" ", $str1);
    my @words2 = split(" ", $str2);

    my $n = scalar(@words1) > scalar(@words2) ? scalar(@words1) : scalar(@words2);

    my $m = &match_arrays(\@words1, \@words2);

    return (100 * $m) / $n;
}

##############################################################################
#
#  #   #       #   #  ###  ####  ####   ####
#  ##  #       #   # #   # #   # #   # #    
#  # # #       # # # #   # ####  #   #  ### 
#  #  ##       # # # #   # #   # #   #     #
#  #   #        # #   ###  #   # ####  #### 
#        #####                              
#                                           
##############################################################################

sub n_words {
    my ($str) = @_;

    $str = &azns($str);

    return scalar(split(" ", $str));
}

##############################################################################
# match_words (str1, str2)
#
#  #   #  ###  #####  #### #   #       #   #  ###  ####  ####   ####
#  ## ## #   #   #   #     #   #       #   # #   # #   # #   # #    
#  # # # #####   #   #     #####       # # # #   # ####  #   #  ### 
#  #   # #   #   #   #     #   #       # # # #   # #   # #   #     #
#  #   # #   #   #    #### #   #        # #   ###  #   # ####  #### 
#                                #####                              
#                                                                   
# As per match_len below, but one word at a time, and the words are
# 'normalized' to have accents removed, etc. using &azns()
##############################################################################

sub match_words {
    my ($str1, $str2, $decay) = @_;

    $str1 = &azns($str1);
    $str2 = &azns($str2);

    my @words1 = split(" ", $str1);
    my @words2 = split(" ", $str2);

    if(defined($decay) && $decay < 1 && $decay > 0) {
        return &match_decay(\@words1, \@words2, $decay);
    }
    else {
        return &match_arrays(\@words1, \@words2);
    }
}

##############################################################################
#
#  #   #  ###  #####  #### #   #       ####  #####  ####  ###  #   #
#  ## ## #   #   #   #     #   #       #   # #     #     #   #  # # 
#  # # # #####   #   #     #####       #   # ####  #     #####   #  
#  #   # #   #   #   #     #   #       #   # #     #     #   #   #  
#  #   # #   #   #    #### #   #       ####  #####  #### #   #   #  
#                                #####                              
#                                                                   
# Give greater priority to earlier matches in the string than to later ones
##############################################################################

sub match_decay {
    my ($array1, $array2, $decay) = @_;

    die "Decay constant $decay must be in ]0, 1]\n" if($decay <= 0 || $decay > 1);

    my @str1 = @$array1;
    my @str2 = @$array2;

    my %counters;
    for(my $i = -1; $i <= $#str1 || $i <= $#str2; $i++) {
        $counters{-1, $i} = 0 if $i <= $#str2;
        $counters{$i, -1} = 0 if $i <= $#str1;
    }
    for(my $i = 0; $i <= $#str1; $i++) {
        my $power = $i;
        for(my $j = 0; $j <= $#str2; $j++) {
            $power = $j if $j < $i;
            if($str1[$i] eq $str2[$j]) {
                $counters{$i, $j} = $counters{$i - 1, $j - 1} + ($decay ** $power);
            }
            else {
                $counters{$i, $j} = 
                    ($counters{$i - 1, $j} > $counters{$i, $j - 1}
                    ? $counters{$i - 1, $j}
                    : $counters{$i, $j - 1});
            }
        }
    }
    return $counters{$#str1, $#str2};
}

##############################################################################
# match_arrays (array1, array2)
#
#  #   #  ###  #####  #### #   #        ###  ####  ####   ###  #   #  ####
#  ## ## #   #   #   #     #   #       #   # #   # #   # #   #  # #  #    
#  # # # #####   #   #     #####       ##### ####  ####  #####   #    ### 
#  #   # #   #   #   #     #   #       #   # #   # #   # #   #   #       #
#  #   # #   #   #    #### #   #       #   # #   # #   # #   #   #   #### 
#                                #####                                    
#                                                                         
# Match two arrays of strings as per match_len below, but item by item rather
# than character by character
##############################################################################

sub match_arrays {
    my ($array1, $array2) = @_;

    my @words1 = @$array1;
    my @words2 = @$array2;

    my $start = 0;
    for(; $start <= $#words1 && $start <= $#words2; $start++) {
        last if($words1[$start] ne $words2[$start]);
    }
    if($start > $#words1) {
        return scalar(@words1);
    }
    elsif($start > $#words2) {
        return scalar(@words2);
    }
    my $end = 0;
    for(; $#words1 - $end >= 0 && $#words2 - $end >= 0; $end++) {
        last if($words1[$#words1 - $end] ne $words2[$#words2 - $end]); 
    }
    if($start > $#words1 - $end) {
        return scalar(@words1);
    }
    elsif($start > $#words2 - $end) {
        return scalar(@words2);
    }

    my %counters;
    for(my $i = $start - 1; $i <= $#words1 - $end; $i++) {
        $counters{$i, $start - 1} = 0;
    }
    for(my $j = $start - 1; $j <= $#words2 - $end; $j++) {
        $counters{$start - 1, $j} = 0;
    }
    for(my $i = $start; $i <= $#words1 - $end; $i++) {
        for(my $j = $start; $j <= $#words2 - $end; $j++) {
            if($words1[$i] eq $words2[$j]) {
                die "$i - 1, $j - 1\n" if !exists($counters{$i - 1, $j - 1});
                $counters{$i, $j} = $counters{$i - 1, $j - 1} + 1;
            }
            else {
                die "$i - 1, $j\n" if !exists($counters{$i - 1, $j});
                die "$i, $j - 1\n" if !exists($counters{$i, $j - 1});
                my $m = $counters{$i - 1, $j};
                $m = $counters{$i, $j - 1} if $counters{$i, $j - 1} > $m;
                $counters{$i, $j} = $m;
            }
        }
    }

    die "($start) $#words1 - $end, $#words2 - $end (", scalar(keys(%counters)),
        ")\n\t", join(" ", @words1), "\n\t", join(" ", @words2), "\n"
        if !exists($counters{$#words1 - $end, $#words2 - $end});

    return $counters{$#words1 - $end, $#words2 - $end} + $start + $end;
}

##############################################################################
# match_len (str1, str2)
#
#  #   #  ###  #####  #### #   #       #     ##### #   #
#  ## ## #   #   #   #     #   #       #     #     ##  #
#  # # # #####   #   #     #####       #     ####  # # #
#  #   # #   #   #   #     #   #       #     #     #  ##
#  #   # #   #   #    #### #   #       ##### ##### #   #
#                                #####                  
#                                                       
# Calculate the number of characters in str1 that are shared in the right
# order with str1. This is e.g. for checking how different author names are.
# 
# After wasting a lot of time trying to work out how to do this efficiently
# myself, I gave up and used the LCSLength algorithm from Wikipedia article
# https://en.wikipedia.org/wiki/Longest_common_subsequence
# (Accessed 14 September 2024 from a very rainy Cracow) with suggested simple
# modifications in that algorithm to make it use less space and time.
##############################################################################

sub match_len {
    my ($str1, $str2) = @_;

    # Trivial cases first
    if(length($str1) == 0 || length($str2) == 0) {
        return 0;
    }
    if($str1 eq $str2) {
        return length($str1);
    }

    # Now the algorithm from Wikipedia
    my @chr1 = split(//, $str1);
    my @chr2 = split(//, $str2);

    my $start = 0;
    for(; $start <= $#chr1 && $start <= $#chr2; $start++) {
        last if($chr1[$start] ne $chr2[$start]);
    }

    my $end = 0;
    for(; $#chr1 - $end >= 0 && $#chr2 - $end >= 0; $end++) {
        last if($chr1[$#chr1 - $end] ne $chr2[$#chr2 - $end]);
    }

    if($start > $#chr1 - $end) {
        return length($str1);
    }
    elsif($start > $#chr2 - $end) {
        return length($str2);
    }

    my %counters;
    for(my $i = $start - 1; $i <= $#chr1 - $end; $i++) {
        $counters{$i, $start - 1} = 0;
    }
    for(my $j = $start - 1; $j <= $#chr2 - $end; $j++) {
        $counters{$start - 1, $j} = 0;
    }
    for(my $i = $start; $i <= $#chr1 - $end; $i++) {
        for(my $j = $start; $j <= $#chr2 - $end; $j++) {
            if($chr1[$i] eq $chr2[$j]) {
                die "$i - 1, $j - 1\n" if !exists($counters{$i - 1, $j - 1});
                $counters{$i, $j} = $counters{$i - 1, $j - 1} + 1;
            }
            else {
                die "$i - 1, $j\n" if !exists($counters{$i - 1, $j});
                die "$i, $j - 1\n" if !exists($counters{$i, $j - 1});
                my $m = $counters{$i - 1, $j};
                $m = $counters{$i, $j - 1} if $counters{$i, $j - 1} > $m;
                $counters{$i, $j} = $m;
            }
        }
    }

    die "($start) $#chr1 - $end, $#chr2 - $end (", scalar(keys(%counters)),
        ")\n\t$str1\n\t$str2\n" if !exists($counters{$#chr1 - $end, $#chr2 - $end});
    return $counters{$#chr1 - $end, $#chr2 - $end} + $start + $end;
}


##############################################################################
# first_eq_len($str1, $str2)
# 
#  #####  ###  ####   #### #####       #####  ###        #     ##### #   #
#  #       #   #   # #       #         #     #   #       #     #     ##  #
#  ####    #   ####   ###    #         ####  # # #       #     ####  # # #
#  #       #   #   #     #   #         #     #  ##       #     #     #  ##
#  #      ###  #   # ####    #         #####  ####       ##### ##### #   #
#                                #####             #####                  
#                                                                         
# Number of characters for which str1 and str2 are the same, when starting 
# at the beginning of the string
##############################################################################

sub first_eq_len {
    my ($str1, $str2) = @_;

    # Trivial cases first
    if(length($str1) == 0 || length($str2) == 0) {
        return 0;
    }
    if($str1 eq $str2) {
        return length($str1);
    }

    my @chr1 = split(//, $str1);
    my @chr2 = split(//, $str2);

    my $i;
    for($i = 0; $i <= $#chr1 && $i <= $#chr2; $i++) {
        return $i if $chr1[$i] ne $chr2[$i];
    }
    return $i;
}

##############################################################################
#   ###  #     #   #  ####
#  #   # #     ##  # #    
#  ##### #     # # #  ### 
#  #   # #     #  ##     #
#  #   # ##### #   # #### 
#                         
# 'Normalize' some text so that it only contains lower-case alphanumeric
# characters separated into words by single spaces, with no space at the
# start or the end
##############################################################################

sub alns {
    my ($txt) = @_;

    $txt = lc($txt);
    $txt =~ s/[^a-z0-9 ]/ /g;
    $txt =~ s/\s+/ /g;
    $txt =~ s/^\s+//;
    $txt =~ s/\s+$//;

    return $txt;
}

##############################################################################
#   ###  ##### #   #  ####
#  #   #    #  ##  # #    
#  #####   #   # # #  ### 
#  #   #  #    #  ##     #
#  #   # ##### #   # #### 
#                         
# As per alns() but remove accents from characters that have them first
##############################################################################

sub azns {
    my ($txt) = @_;

    $txt = &Latin::atoz($txt);

    return &alns($txt);
}
