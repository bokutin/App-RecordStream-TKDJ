package App::RecordStream::TKDJ;
$App::RecordStream::TKDJ::VERSION = '0.02';
use strict;
use 5.010;

# For informational purposes only in the fatpacked file, so it's OK to fail.
# For now, classes are still under the App::RecordStream::Operation namespace
# instead of ::TKDJ::Operation.
eval {
    require App::RecordStream::Site;
    App::RecordStream::Site->register_site(
        name => __PACKAGE__,
        path => __PACKAGE__,
    );
};

1;
