package App::RecordStream::Operation::fromtkdjschedule;

use utf8;
use Modern::Perl;
use base qw(App::RecordStream::Operation);

use Algorithm::Combinatorics;
use Cache::File;
use Encode;
use File::Spec;
use IO::All;
use IPC::Run qw(run);
use List::Util qw(min max uniq sum);
use List::UtilsBy qw(nsort_by min_by uniq_by);
use Math::Round qw(round);
use Scalar::Util qw(refaddr);
use Set::IntSpan;
use Storable qw(freeze thaw);
use Text::Trim;
use URI::Fetch;
use XML::Twig;

my $URI = "https://tkdj.net/data/schedule.pdf";

sub init {
    my $self = shift;
    my $args = shift;

    my $pages;
    my $spec = {
        "pages=s" => \$pages,
    };
    $self->parse_options($args, $spec);

    $self->{pages} = { map { $_ => 1 } split /,/, $pages } if $pages;
}

sub wants_input { 0 }

sub stream_done {
    my ($this) = @_;

    my $parsed = $this->get_parsed;
    for my $p (1..$parsed->{num_pages}) {
        next if $this->{pages} and !$this->{pages}{$p};
        $this->get_page_records($parsed,$p);
    }
}

sub usage {
    <<USAGE;
Usage: recs-fromtkdjschedule <args>
     Prints out JSON records converted from $URI

Examples:
     Get records for all pages.
            recs-fromtkdjschedule
     Only get pages 1, 2 and 3
            recs-fromtkdjschedule --pages 1,2,3
USAGE
}

##########################################################################################

sub cache {
    my ($this) = @_;
    $this->{cache} ||= do {
        my $dir   = File::Spec->catdir( File::Spec->tmpdir, 'recs-fromtkdjschedule/cache' );
        my $cache = Cache::File->new( cache_root => $dir );
    };
}

sub get_page_records {
    my ($this, $parsed, $p) = @_;

    my $svg = XML::Twig->new(
        pretty_print => 'indented',
        twig_handlers => {
            image    => sub { $_->delete },
            symbol   => sub { $_->delete },
            clipPath => sub { $_->delete },
            use      => sub { $_->delete },
        },
        elt_class    => 'App::RecordStream::Operation::fromtkdjschedule::Elt',
    );
    $svg->parse($parsed->{svg}[$p-1]);

    my @lines  = $svg->find_nodes('//path[!@fill]');
    my @vlines = uniq_by { refaddr $_->{path} } grep $_->{direction} eq 'vertical',   map $_->path2lines, @lines;
    my @hlines = uniq_by { refaddr $_->{path} } grep $_->{direction} eq 'horizontal', map $_->path2lines, @lines;
    my @wlines = map $_->path2lines, $svg->find_nodes('//path[@fill="#333333"]'); # 週のライン

    my @divbox;
    for my $rawbox ( $svg->find_nodes('//path[@fill!="#ffffff"]') ) {
        my @lines = $rawbox->path2lines;
        next if $lines[2]{y} <= $wlines[2]{y}+10; # 週より上は無視
        my $x1 = $lines[0]{x1};
        my $x2 = $lines[0]{x2};
        my $y1 = $lines[1]{y1};
        my $y2 = $lines[1]{y2};
        my $divbox = { x1 => $x1, x2 => $x2, y1 => $y1, y2 => $y2, bg => $rawbox->att('fill') };
        push @divbox, $divbox;
    }
    my sub split_by_vlines {
        my ($divbox) = @_;

        my $middle = ($divbox->{y1}+$divbox->{y2})/2;
        my @div    = 
            nsort_by { $_->{x} }
            grep { abs $_->{x}-$divbox->{x1} >= 1 and abs $_->{x}-$divbox->{x2} >= 1 }
            grep { $divbox->{x1} <= $_->{x} and $_->{x} <= $divbox->{x2} }
            grep { $_->{y1} <= $middle and $middle <= $_->{y2} } @vlines;

        my @divbox;
        my %right = %$divbox;
        for (@div) {
            my %left = ( %right, x2 => $_->{x} );
            push @divbox, \%left;
            $right{x1} = $_->{x};
        }
        push @divbox, \%right;
        @divbox;
    };
    my sub split_by_hlines {
        my ($divbox) = @_;

        my $center = ($divbox->{x1}+$divbox->{x2})/2;
        my @div    = 
            nsort_by { $_->{y} }
            grep { abs $_->{y}-$divbox->{y1} >= 1 and abs $_->{y}-$divbox->{y2} >= 1 }
            grep { $divbox->{y1} <= $_->{y} and $_->{y} <= $divbox->{y2} }
            grep { $_->{x1} <= $center and $center <= $_->{x2} } @hlines;

        my @divbox;
        my %bottom = %$divbox;
        for (@div) {
            my %top = ( %bottom, y2 => $_->{y} );
            push @divbox, \%top;
            $bottom{y1} = $_->{y};
        }
        push @divbox, \%bottom;
        @divbox;
    };
    @divbox = map split_by_vlines($_), @divbox;
    @divbox = map split_by_hlines($_), @divbox;
    $_->{center} = ($_->{x2}+$_->{x1})/2 for @divbox;
    $_->{middle} = ($_->{y2}+$_->{y1})/2 for @divbox;

    my $lesson_num_last = 0;
    {
        my @h; # 上下のお隣さん。同色で且つ間に分割線がない
        my @v; # 左右のお隣さん。同色で且つ間に分割線がない
        my $citer = Algorithm::Combinatorics::combinations(\@divbox, 2);
        while ( my $c = $citer->next ) {
            my ($d1, $d2) = @$c;
            next unless $d1->{bg} eq $d2->{bg};
            {
                my $range1 = Set::IntSpan->new(int($d1->{x1}).'-'.int($d1->{x2}));
                my $range2 = Set::IntSpan->new(int($d2->{x1}).'-'.int($d2->{x2}));
                my $span1  = $range1*$range2;
                my $len    = $span1 =~ /^(\d+)-(\d+)$/ ? $2-$1 : 0;
                if ( $len >= 5 ) {
                    #my ($xa, $xb) = ($1, $2);
                    my $y = 0;
                    if ( abs($d1->{y1}-$d2->{y2}) < 5 ) {
                        $y = ($d1->{y1}+$d2->{y2})/2;
                    }
                    elsif ( abs($d2->{y1}-$d1->{y2}) < 5 ) {
                        $y = ($d2->{y1}+$d1->{y2})/2;
                    }
                    if ( $y ) {
                        my @found =
                            grep {
                                my $range3 = Set::IntSpan->new(int($_->{x1})."-".int($_->{x2}));
                                my $span2  = $span1*$range3;
                                $span2 =~ /^(\d+)-(\d+)$/ ? abs($2-$1) > 5 : 0;
                            }
                            grep { abs($_->{y}-$y) < 5 } @hlines;
                        if (!@found) {
                            push @h, [ $d1, $d2 ];
                        }
                    }
                }
            }
            {
                my $range1 = Set::IntSpan->new(int($d1->{y1}).'-'.int($d1->{y2}));
                my $range2 = Set::IntSpan->new(int($d2->{y1}).'-'.int($d2->{y2}));
                my $span1  = $range1*$range2;
                my $len    = $span1 =~ /^(\d+)-(\d+)$/ ? $2-$1 : 0;
                if ( $len >= 5 ) {
                    my ($ya, $yb) = ($1, $2);
                    my $x = 0;
                    if ( abs($d1->{x1}-$d2->{x2}) < 5 ) {
                        $x = ($d1->{x1}+$d2->{x2})/2;
                    }
                    elsif ( abs($d2->{x1}-$d1->{x2}) < 5 ) {
                        $x = ($d2->{x1}+$d1->{x2})/2;
                    }
                    if ( $x ) {
                        my @found =
                            grep {
                                my $range3 = Set::IntSpan->new(int($_->{y1})."-". int($_->{y2}));
                                my $span2  = $span1*$range3;
                                $span2 =~ /^(\d+)-(\d+)$/ ? abs($2-$1) > 5 : 0;
                            }
                            grep { abs($_->{x}-$x) < 5 } @vlines;
                        if (!@found) {
                            push @v, [ $d1, $d2 ];
                        }
                    }
                }
            }
        }
        #say 0+@h;
        #say 0+@v;

        # 横グループと縦グループを統合する
        for (@h, @v) {
            my ($lesson_num) = grep $_, map $_->{lesson_num}, @$_;
            $lesson_num ||= ++$lesson_num_last;
            for (@$_) {
                $_->{lesson_num} ||= $lesson_num;
            }
        }
        for (@divbox) {
            $_->{lesson_num} ||= ++$lesson_num_last;
        }
        #say $lesson_num_last; # 156になるはず
    }

    # trace から divbox へ fill_text を足していく
    my $trace = XML::Twig->new(
        pretty_print => 'indented',
        elt_class    => 'App::RecordStream::Operation::fromtkdjschedule::Elt',
    );
    $trace->parse($parsed->{trace}[$p-1]);
    for my $text ($trace->find_nodes('//fill_text')) {
        my $pos = $text->text_potision;
        my @found = grep {
            $_->{x1} <= $pos->{center} and $pos->{center} <= $_->{x2}
                and
            $_->{y1} <= $pos->{middle} and $pos->{middle} <= $_->{y2}
        } @divbox;
        if (@found == 1) {
            my $divbox = $found[0];
            push @{$divbox->{text}}, $text;
        }
        # elsif (@found == 0) {
        #     warn "0=".encode_utf8 str($text);
        # }
        # elsif (@found > 1) {
        #     warn "1>".encode_utf8 str($text);
        # }
    }

    # divbox ごとに最も近い週をセット
    {
        my @weeks = grep $_->str =~ /^.曜$/, $trace->find_nodes('//fill_text');
        die unless @weeks == 7;
        for my $d (@divbox) {
            my @near = nsort_by {
                my $pos = $_->text_potision;
                sqrt( abs($d->{center}-$pos->{x})**2 + abs($d->{middle}-$pos->{y})**2 );
            } @weeks;
            $d->{week} = $near[0]->str;
        }
    }

    # divbox ごとに開始時間、終了時間をセット。解像度は30分
    {
        my @weeks  = grep { $_->att('fill')//'' =~ /#333333|#0000ff|#ff0000/ } $svg->find_nodes('//path');
        die 0+@weeks unless @weeks >= 3;
        state $top = min map $_->{y1}, @divbox; # FIXME
        my $bottom = max map $_->{y2}, @divbox;
        my $stepwidth = ($bottom-$top)/((23-7)*2); # 7:00-23:00
        for my $d (@divbox) {
            $d->{start} = 7 + round(($d->{y1}-$top)/$stepwidth)*0.5;
            $d->{end}   = 7 + round(($d->{y2}-$top)/$stepwidth)*0.5;
        }
    }

    my $dojo = "";
    for my $text ($trace->find_nodes('//fill_text')) {
        if ( $text->str =~ /^\s*★.*★\s*$/ ) {
            $dojo = $&;
            $dojo =~ s/★|\d+月時間割//g;
            $dojo =~ s/\s+/ /g;
            $dojo = trim $dojo;
            last;
        }
    }

    for my $lesson_num (1..$lesson_num_last) {
        my @matches = grep $_->{lesson_num} == $lesson_num, @divbox;
        my @text    =
            map { trim $_->str }
            nsort_by { $_->text_potision->{distance} }
            map { @{$_->{text}||[]} } @matches;

        my %r;
        $r{yyyymm} = $parsed->{yyyymm};
        $r{page}   = $p;
        $r{dojo}   = $dojo;
        $r{week}   = join ",", uniq map $_->{week}, @matches;
        $r{start}  = min map $_->{start}, @matches;
        $r{end}    = max map $_->{end},   @matches;
        $r{dow}    = do {
            state $map = { "月曜", => 1, "火曜", => 2, "水曜", => 3, "木曜", => 4, "金曜", => 5, "土曜", => 6, "日曜", => 7 };
            $map->{$r{week}};
        };
        $r{text}   = join ",", @text;

        my @note;
        @text = grep length, map {
            if (!$r{time} and s/\d+[:：]\d+//) {
                $r{time} = $& =~ s/：/:/r;
            }
            if (!$r{instructor} and s/(.*?)(?:・(1回\d+円))?(★+)//) {
                $r{instructor} = $1;
                push @note, $2 if $2;
                $r{hard}       = length $3;
            }
            if (s/[\(（]([^\)）]+)[\)）]//) {
                local $_ = $1;
                if (!$r{instructor} and !/体験/) {
                    $r{instructor} = $_;
                }
                else {
                    push @note, $_;
                }
            }
            trim $_;
        } @text;
        $r{note} = join ",", @note;
        $r{menu} = join "", @text;

        $r{$_} = encode_utf8 $r{$_} for keys %r;
        $this->push_record(\%r);
    }
}

sub get_parsed {
    my ($this) = @_;

    my $pdf = $this->get_pdf;
    my $parsed_key = "parsed-".$pdf->last_modified;
    #$this->cache->remove($parsed_key);
    $this->cache->exists($parsed_key) and return thaw $this->cache->get($parsed_key);

    my $pdfinfo   = do { run [qw(pdfinfo -)], \$pdf->content, \my $out or die $?; decode_utf8 $out };
    my $yyyymm    = $pdfinfo =~ /^Title:\s*(\d{4})年(\d{1,2})月時間割/m ? sprintf '%04d%02d', $1, $2 : die;
    my $num_pages = $pdfinfo =~ /^Pages:\s*(\d+)/m ? $1 : die;
    my $pdf_abs   = $this->save_pdf($pdf, $yyyymm);

    my $trace_xml = do { run [qw(mutool draw -o - -F trace), $pdf_abs], \undef, \my $out, \my $err or die $?; $out };
    my $svg_xml   = do { run [qw(mutool draw -o - -F svg  ), $pdf_abs], \undef, \my $out, \my $err or die $?; $out };
    
    my @trace = split /^(?=<\?xml)/m, $trace_xml;
    my @svg   = split /^(?=<\?xml)/m, $svg_xml;
    die unless @trace == $num_pages;
    die unless @svg   == $num_pages;

    my $parsed = {
        num_pages => $num_pages,
        pdfinfo   => $pdfinfo,
        yyyymm    => $yyyymm,
        trace     => \@trace,
        svg       => \@svg,
    };
    $this->cache->set($parsed_key, freeze $parsed);

    $parsed;
}

sub get_pdf {
    my ($this) = @_;
    my $res = URI::Fetch->fetch( $URI, Cache => $this->cache, NoNetwork => 3600 ) or die URI::Fetch->errstr;
}

sub save_pdf {
    my ($this, $pdf, $yyyymm) = @_;

    my $dir = File::Spec->catdir( File::Spec->tmpdir, 'recs-fromtkdjschedule' );
    my $basename = join("-", grep $_, $yyyymm, $pdf->last_modified) . ".pdf";
    my $abs = File::Spec->catfile($dir, $basename);
    -f $abs or io($abs)->binary->print($pdf->content);
    $abs;
}

package App::RecordStream::Operation::fromtkdjschedule::Elt;

use Modern::Perl;
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

    $elt->latt('#text_position') //= do {
        my @g = $elt->find_nodes('.//g');
        die unless @g >= 1;
        my @m = split /\s/, $elt->att('matrix');
        die unless @m == 6;
        my ($a, $b, $c, $d, $e, $f) = @m;
        my $x = $g[0]->att('x')*$a+$e;
        my $y = $g[0]->att('y')*$d+$f;
        my $center = $g[ceil($#g/2)]->att('x')*$a+$e;
        my $middle = $g[0]->att('y')*$d+$f;

        +{
            x        => $x,
            y        => $y,
            center   => $center,
            middle   => $middle,
            distance => sqrt($x**2 + $y**2),
        };
    };
}

1;

__END__

ターム 呼び分け

    rawbox ... SVGの実際の長方形
    divbox ... rawboxを罫線を考慮して分割した仮想の長方形
    lesson ... 目視で分かる実際のレッスンの枠

注意点

    横や縦に長い rawbox が罫線で区切られていて複数の lesson になっているものがある
        rawbox
            +-----------------------------+
            |                             |
            +-----------------------------+
        lesson
            +-----------------------------+
            |         |         |         |
            +-----------------------------+

    一つの lesson が複数の rawbox で構成されている場合がある
        lesson
            +---------+
            |         |
            |         |
            |         |
            +---------+
        rawbox
            +---------+
            |         |
            |---------|
            |         |
            +---------+

    一つの lesson は長方形とは限らない
        lesson
            +---------+
            |         |
            |         |
            |    +----+
            |    |
            +----+

    分割して統合する必要のある分けかたになっているものもある
        rawbox
            +-------------------+
            |                   |
            +-------------------+
            |         |
            +---------+
        lesson
            +-------------------+
            |         |         |
            +         +---------+
            |         |
            +---------+

    lesson の区切りの線が半端なものがある
        lesson
            +---------+
            |         
            |         
            |         |
            |         |
            +---------+

戦略

    lesson 1:n divbox の対応を作る。

        rawbox を罫線で分割し divbox を作る。

        罫線で区切られていない隣りあう同色の divbox を一つの lesson とする

    テキストはどの divbox に所属しているか位置から引き lesson 1:n text の対応を作る。
