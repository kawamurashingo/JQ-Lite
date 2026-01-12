use strict;
use warnings;
use Test::More;
use JQ::Lite;

my $jq = JQ::Lite->new;

my $json = q({"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Ben"}]});

my @names = $jq->run_query($json, '.users[] | . as $u | $u.name');
is_deeply(\@names, ['Ada', 'Ben'], 'as binding stays aligned with each pipeline item');

my @objects = $jq->run_query($json, '.users[] | . as $u | $u');
is_deeply(
    \@objects,
    [
        { id => 1, name => 'Ada' },
        { id => 2, name => 'Ben' },
    ],
    'as binding returns the original object per element'
);

my @pipeline = $jq->run_query($json, '.users[] | . as $u | $u.id | . + 10');
is_deeply(\@pipeline, [11, 12], 'as binding persists across downstream pipeline steps');

done_testing();
