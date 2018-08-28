package App::TKDJSchedule::XMLTwigElt;
$App::TKDJSchedule::XMLTwigElt::VERSION = '0.02';
use Modern::Perl;
use XML::Twig;
use base qw(XML::Twig::Elt);

use POSIX qw(ceil);

sub path2lines {
    my ($elt) = @_;

    my $ref = $elt->latt('#path2lines') //= do {
        die unless $elt->att('transform') =~ /^matrix\(([^\)]+)\)$/;
        my @m = split /,/, $1;
        die $elt->att('transform') unless @m == 6;
        my ($a, $b, $c, $d, $e, $f) = @m;
        die unless $a == 1;
        die unless $b == 0;
        die unless $c == 0;
        die unless $d == -1;
        die unless $e == 0;
        die unless $f == 595;
        die unless $elt->att('d') =~ m/^M ([\d.]+) ([\d.]+) L ([\d.]+) ([\d.]+) L ([\d.]+) ([\d.]+) L ([\d.]+) ([\d.]+) Z $/;

        my @lines;

        die unless $2 == $4;
        die unless $1 < $3;
        push @lines, { x1 => $1*$a+$e, x2 => $3*$a+$e, y => $2*$d+$f, path => $elt, direction => 'horizontal' }; #top
        die unless $3 == $5;
        die unless $4 < $6;
        push @lines, { y2 => $4*$d+$f, y1 => $6*$d+$f, x => $3*$a+$e, path => $elt, direction => 'vertical' };   #right
        die unless $6 == $8;
        die unless $7 < $5;
        push @lines, { x1 => $7*$a+$e, x2 => $5*$a+$e, y => $6*$d+$f, path => $elt, direction => 'horizontal' }; #bottom
        die unless $7 == $1;
        die unless $2 < $8;
        push @lines, { y2 => $2*$d+$f, y1 => $8*$d+$f, x => $7*$a+$e, path => $elt, direction => 'vertical' };   #left

        \@lines;
    };
    @$ref;
}

sub str {
    my ($elt) = @_;
    $elt->latt('#str') //= 
        join "", map $_->att('unicode') =~ s/^U\+(\S+)$/chr hex $1/gre, $elt->descendants('g');
}

sub text_potision {
    my ($elt) = @_; # fill_text

    # <fill_text color="1" colorspace="DeviceGray" matrix="1 0 0 -1 0 612">
    #   <span bidi="0" font="BCDGEE+MS Gothic" trm="10.8 0 0 10.8" wmode="0">
    #     <g glyph="8518" unicode="U+706b" x="182.54" y="412.03"/>
    #     <g glyph="7001" unicode="U+66dc" x="193.34" y="412.03"/>
    #   </span>
    # </fill_text>
    #
    # g が一文字に対応。xyの位置は左下。
    # fill matrix= は位置の変換行列。
    #   https://developer.mozilla.org/ja/docs/Web/SVG/Attribute/transform
    # span trm=
    #   https://github.com/ArtifexSoftware/mupdf/blob/709b4b95e1b30a62511234773fb53f75a40279f3/include/mupdf/fitz/geometry.h#L246

    $elt->latt('#text_position') //= do {
        my @g = $elt->find_nodes('.//g');
        #warn $elt->sprint;
        die unless @g >= 1;
        my @m = split /\s/, $elt->att('matrix');
        die unless @m == 6;
        my ($a, $b, $c, $d, $e, $f) = @m;
        # xyの位置は最初の文字の左下
        my $x = $g[0]->att('x')*$a+$e;
        my $y = $g[0]->att('y')*$d+$f;
        # centerとmiddleはTTFから計算しないと、正確には求まらない。
        #   centerは最後の文字の横幅を
        #   middleは最も高さのある文字の高さを計算する必要がある。
        # 簡単と計算コストの為、端折る。
        #my $center = $g[ceil($#g/2)]->att('x')*$a+$e;
        my $center = do {
            my $x_start = $x;
            my $x_last  = $g[-1]->att('x')*$a+$e;
            my $char_width = do {
                if (@g > 1) {
                    my $ave_width = ($x_last-$x_start)/$#g;
                }
                else {
                    5;
                }
            };
            my $center = $x_start+((($x_last+$char_width)-$x_start)/2);
        };
        my $char_height = do {
            if (@g > 1) {
                my $x_start    = $x;
                my $x_last     = $g[-1]->att('x')*$a+$e;
                my $ave_width  = ($x_last-$x_start)/$#g;
                my $ave_height = $ave_width;
            }
            else {
                10;
            }
        };
        my $top    = $y-$char_height;
        my $middle = $y-($char_height/2);

        +{
            x        => $x,
            y        => $y,
            center   => $center,
            middle   => $middle,
            top      => $top,
            distance => sqrt($x**2 + $y**2),
        };
    };
}

1;
