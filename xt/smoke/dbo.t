#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Test;
use Log::Log4perl::Level;
use Test::File::Contents;
use Test::Deep;
use YAML::Syck qw(LoadFile);

my $report = get_report_from_strategy(
    code => 'TX', tf => 'day',
    start => '2001-01-01 00:00:00',
    end => '2011-01-01 00:00:00',
    strategy => 'DBO',
);

is_report_identical($report, 'dbo-expected.csv');

# for debugging:
#Log::Log4perl->reset;
#Log::Log4perl->easy_init($INFO);

my $state_file = File::Temp->new;
$report = get_report_from_strategy(
    code => 'TX', tf => 'day',
    start => '2010-01-01 00:00:00',
    end => '2010-01-22 00:00:00',
    strategy => 'DBO',
    args => ['--state_file', $state_file->filename]
);

cmp_deeply(LoadFile($state_file),
           { date => '2010-01-21 00:00:00',
             fsa => [{
                 curr_state => 'pending',
                 notes => {
                     dir => -1,
                     fsa_start => 13,
                     order => {
                         dir => -1,
                         price => 8101,
                         qty => 1,
                         type => 'stp',
                     },
                     order_annotation => {
                         r => 163,
                     },
                     order_id => re('^s.*$'),
                     order_price => 8101,
                     qty => 1,
                     stp_price => '8264'
                 }
             }, {
                 curr_state => 'pending',
                 notes => {
                     dir => 1,
                     fsa_start => 13,
                     order => {
                         dir => 1,
                         price => 9116,
                         qty => 1,
                         type => 'stp',
                     },
                     order_annotation => {
                         r => 183,
                     },
                     order_id => re('^s.*$'),
                     order_price => 9116,
                     qty => 1,
                     stp_price => '8933'
                 },
             }]
         }, 'no actual order');


$report = get_report_from_strategy(
    code => 'TX', tf => 'day',
    start => '2010-01-22 00:00:00',
    end => '2010-01-23 00:00:00',
    strategy => 'DBO',
    args => ['--state_file', $state_file->filename]
);

cmp_deeply(LoadFile($state_file->filename),
           { date => '2010-01-22 00:00:00',
             fsa => [{
                 curr_state => 'entered',
                 notes => {
                     dir => -1,
                     entry_price => 8019,
                     fsa_start => 13,
                     order => {
                         dir => -1,
                         price => 8101,
                         qty => 1,
                         type => 'stp',
                     },
                     order_annotation => {
                         r => 163,
                     },
                     order_id => re('^s.*$'),
                     order_price => 8101,
                     qty => 1,
                     stp_price => '8264',
                     submit_i => 13
                 }
             }]}, 'entered');

$report = get_report_from_strategy(
    code => 'TX', tf => 'day',
    start => '2010-01-23 00:00:00',
    end => '2010-03-08 00:00:00',
    strategy => 'DBO',
    args => ['--state_file', $state_file->filename]
);

cmp_deeply(LoadFile($state_file->filename),
           { date => '2010-03-05 00:00:00',
             fsa => [{
                 curr_state => 'entered',
                 notes => {
                     dir => -1,
                     entry_price => 8019,
                     fsa_start => 13,
                     order => {
                         dir => -1,
                         price => 8101,
                         qty => 1,
                         type => 'stp',
                     },
                     order_annotation => {
                         r => 163,
                     },
                     order_id => re('^s.*$'),
                     order_price => 8101,
                     qty => 1,
                     stp_price => 7708,
                     submit_i => 13
                 }
             }]}, 'entered');

$report = get_report_from_strategy(
    code => 'TX', tf => 'day',
    start => '2010-03-08 00:00:00',
    end => '2010-03-09 00:00:00',
    strategy => 'DBO',
    args => ['--state_file', $state_file->filename]
);


cmp_deeply(LoadFile($state_file->filename),
           { date => '2010-03-08 00:00:00',
             fsa => [{
                 curr_state => 'pending',
                 notes => {
                     dir => -1,
                     fsa_start => 39,
                     order => {
                         dir => -1,
                         price => 7056,
                         qty => 1,
                         type => 'stp',
                     },
                     order_annotation => {
                         r => 142,
                     },
                     order_id => re('^s.*$'),
                     order_price => 7056,
                     qty => 1,
                     stp_price => '7198'
                 }
             }, {
                 curr_state => 'pending',
                 notes => {
                     dir => 1,
                     fsa_start => 39,
                     order => {
                         dir => 1,
                         price => 7758,
                         qty => 1,
                         type => 'stp',
                     },
                     order_annotation => {
                         r => 156,
                     },
                     order_id => re('^s.*$'),
                     order_price => 7758,
                     qty => 1,
                     stp_price => '7602'
                 },
             }]
         }, 'no actual order');

file_contents_eq($report, <<EOF
id,date,dir,open_date,close_date,open_price,close_price,profit,exit_type,r
201003-001,2010-03-08,-1,2010-03-05 00:00:00,2010-03-08 00:00:00,8019,7729,290,stp,163
EOF
);
done_testing();

