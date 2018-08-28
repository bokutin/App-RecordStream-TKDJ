package App::RecordStream::Operation::fromtkdjschedule;
$App::RecordStream::Operation::fromtkdjschedule::VERSION = '0.02';
use Modern::Perl;
use base qw(App::RecordStream::Operation);

use IO::All;

sub init {
    my $this = shift;
    my $args = shift;

    my $spec = {
        "cache_re=s" => \$this->{'cache_re'},
    };

    $this->parse_options($args, $spec);
}

sub wants_input { 0 }

sub stream_done {
    my ($this) = @_;

    my $cache_dir = File::Spec->catdir($ENV{HOME}, ".tkdjschedule/cache");
    my $file      = -d $cache_dir && do {
        my $re = $this->{cache_re} || '.';
        (grep /$re/, grep /\.jsonl$/, io->catdir($cache_dir)->All_Files)[-1];
    };
    unless ($file) {
        die "Parsed jsonl file not found. Please execute tkdjschedule-update first.";
    }

    $this->update_current_filename("$file");

    my $content  = "[" .  $file->all=~s/}\K(?=\n\{)/,/gr . "]";
    my $arrayref = JSON::MaybeXS->new->decode($content);

    $this->push_record($_) for map +(bless $_, 'App::RecordStream::Record'), @$arrayref;
}

sub usage {
    <<USAGE;
Usage: recs-fromtkdjschedule <args>
     Prints out JSON records converted from https://tkdj.net/data/schedule.pdf

USAGE
}

1;
