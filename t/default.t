use strict;
use warnings;
use Test::More;
use JSON::PP;
use JQ::Lite;

my $jq = JQ::Lite->new;

subtest 'default() preserves defined values' => sub {
    my $json = '{"nickname":"alice","zero":0,"active":false,"blank":""}';
    my @name = $jq->run_query($json, '.nickname | default("unknown")');
    is($name[0], 'alice', 'default() does not override existing string');

    my @count = $jq->run_query($json, '.zero | default(5)');
    is($count[0], 0, 'default() does not override numeric zero');

    my @active = $jq->run_query($json, '.active | default(true)');
    is($active[0], JSON::PP::false, 'default() does not override boolean false');

    my @empty = $jq->run_query($json, '.blank | default("fallback")');
    is($empty[0], '', 'default() does not override empty strings');
};

subtest 'default() applies to missing and null values' => sub {
    my $json = '{"nickname":null}';
    my @missing = $jq->run_query($json, '.missing | default("unknown")');
    is($missing[0], 'unknown', 'default() applies to missing field');

    my @null_value = $jq->run_query($json, '.nickname | default("unknown")');
    is($null_value[0], 'unknown', 'default() applies to null');
};

subtest 'default() supports literal fallbacks' => sub {
    my @number = $jq->run_query('{}', '.missing | default(42)');
    is($number[0], 42, 'default() uses numeric literals');

    my @boolean = $jq->run_query('{}', '.missing | default(true)');
    is($boolean[0], JSON::PP::true, 'default() uses boolean literals');

    my @array = $jq->run_query('{}', '.missing | default([1,2,3])');
    is_deeply($array[0], [1, 2, 3], 'default() uses array literals');

    my @object = $jq->run_query('{}', '.missing | default({"a":1})');
    is_deeply($object[0], { a => 1 }, 'default() uses object literals');

    my @single_quote = $jq->run_query('{}', ".missing | default('fallback')");
    is($single_quote[0], 'fallback', 'default() supports single-quoted strings');
};

done_testing();
