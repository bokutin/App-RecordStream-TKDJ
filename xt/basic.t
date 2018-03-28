use Modern::Perl;
use Test::More;

use Encode;
use IO::All;
use IPC::Run qw(run);
use List::Util qw(sum);
use Test::Differences;

# page1

my $src = do {
    run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 1"], \undef, \my $out or die;
    $out;
};

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",25
"火曜",25
"水曜",23
"木曜",25
"金曜",20
"土曜",24
"日曜",14

    eq_or_diff $out, $expected;
}

{
    my $out = do {
        run [qw(sh -c), "grep ダイエットキック | recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",1
"火曜",4
"水曜",2
"木曜",2
"金曜",2
"土曜",2

    eq_or_diff $out, $expected;
}

is 0+(split /\n/, $src), sum(25, 25, 23, 25, 20, 24, 14);

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dojo | recs-eval '\$r->{dojo}'"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
中野トイカツ道場

    eq_or_diff $out, $expected;
}

# page2

$src = do {
    run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 2"], \undef, \my $out or die;
    $out;
};

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",7
"火曜",13
"水曜",7
"木曜",11
"金曜",7
"土曜",6
"日曜",8

    eq_or_diff $out, $expected;
}

# page3

$src = do {
    run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 3"], \undef, \my $out or die;
    $out;
};

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",16
"火曜",16
"水曜",16
"木曜",16
"金曜",17
"土曜",9
"日曜",10

    eq_or_diff $out, $expected, 'page3';
}

{
    my $out = do {
        run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 1,2,3 | recs-grep '\$r->{dow}==1' | recs-collate -k dojo -a min,start | recs-sort -k dojo | recs-tocsv"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
dojo,min_start
"キックボクシング&柔術 高田馬場道場",16
"ファイティングラボ高田馬場",7
"中野トイカツ道場",7

    eq_or_diff $out, $expected;
}

# page10

$src = do {
    run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 10"], \undef, \my $out or die;
    $out;
};

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",13
"火曜",18
"水曜",18
"木曜",15
"金曜",15
"土曜",9
"日曜",7

    eq_or_diff $out, $expected, 'page10';
}

# page12

$src = do {
    run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 12"], \undef, \my $out or die;
    $out;
};

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",20
"火曜",20
"水曜",17
"木曜",21
"金曜",18
"土曜",19
"日曜",15

    eq_or_diff $out, $expected, 'page12';
}

# page14

$src = do {
    run [qw(sh -c), "$^X -I lib ./script/recs-fromtkdjschedule --pages 14"], \undef, \my $out or die;
    $out;
};

{
    my $out = do {
        run [qw(sh -c), "recs-collate -k dow,week -a count | recs-sort -k dow | recs-tocsv -k week,count"], \$src, \my $out or die;
        $out;
    };
    my $expected = <<'';
week,count
"月曜",21
"火曜",15
"水曜",15
"木曜",18
"金曜",19
"土曜",12
"日曜",16

    eq_or_diff $out, $expected, 'page14';
}

done_testing;
