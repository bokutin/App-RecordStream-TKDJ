use utf8;
use Modern::Perl;
use Test::More;

use Encode;
use IPC::Run qw(run);
use Text::Diff;

sub check_diff {
    my ($paste) = @_;
    my ($cmd, $expected) = split /\R/, $paste, 2;
    $cmd =~ s/.* % //;
    my $out = do {
        run [qw(sh -c), $cmd], '>',\my $out or die $?;
        decode_utf8 $out;
    };
    s/ *$//mg for $out, $expected;
    my $diff = diff \$out, \$expected, { STYLE => "Unified", FILENAME_A => 'out', FILENAME_B => 'expected' };
    if (length $diff) {
        ok 0, "diff";
        diag encode_utf8 $diff;
    }
    else {
        ok 1, "diff";
    }
}

check_diff <<'';
oka bokutin % script/recs-fromtkdjschedule --cache_re 20180820 | ack 新宿 | ack 木曜 | recs-sortnatural -k dow,start_h | head -4 | recs-totablewide -k dojo,week,hard,start,end,class,instructor
dojo                   week   hard   start   end   class                      instructor
--------------------   ----   ----   -----   ---   ------------------------   ----------
ファイトフィット新宿   木曜   1      7:10    8     モーニングキック           石戸谷
ファイトフィット新宿   木曜   1      8:00    9     キックボクシング           石戸谷
ファイトフィット新宿   木曜   1      9:00    10    超初心者キックボクシング   石戸谷
ファイトフィット新宿   木曜   1      10:00   12    ダイエットキック           石戸谷

done_testing;
