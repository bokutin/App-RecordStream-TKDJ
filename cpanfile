requires 'perl', '5.010001';

requires 'Algorithm::Combinatorics';
requires 'Cache::File';
requires 'IO::All';
requires 'IPC::Run';
requires 'List::Util';
requires 'List::UtilsBy';
requires 'Math::Round';
requires 'Set::IntSpan';
requires 'Text::Trim';
requires 'URI::Fetch';
requires 'XML::Twig';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::Differences', '0.98';
};
