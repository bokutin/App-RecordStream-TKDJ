package App::RecordStream::TKDJ;

use strict;
use 5.010;
our $VERSION = '0.01';

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

__END__

=encoding utf-8

=head1 NAME

App::RecordStream::TKDJ - It's new $module

=head1 SYNOPSIS

    use App::RecordStream::TKDJ;

=head1 DESCRIPTION

App::RecordStream::TKDJ is ...

=head1 LICENSE

Copyright (C) Tomohiro Hosaka.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Tomohiro Hosaka E<lt>bokutin@bokut.inE<gt>

=cut

