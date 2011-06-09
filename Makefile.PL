use inc::Module::Install;
name 'TradeSpring';
all_from 'lib/TradeSpring.pm';
readme_from 'lib/TradeSpring.pm';
build_requires 'Test::More';
auto_include_deps;
author_tests('xt');

requires 'Term::ANSIScreen';
requires 'MooseX::Log::Log4perl';
requires 'Log::Log4perl';
requires 'Net::Address::IP::Local';
requires 'MooseX::SimpleConfig';
requires 'MooseX::Getopt';
requires 'Test::File::Contents';
requires 'UNIVERSAL::require';
requires 'Method::Signatures::Simple';
requires 'Number::Extreme';
requires 'MooseX::ClassAttribute';
requires 'DateTime::Format::Strptime';
requires 'List::MoreUtils';
requires 'List::AllUtils';
requires 'UNIVERSAL::require';
requires 'Graph';

requires 'Math::Random::MT';

requires 'Statistics::Basic';

WriteAll;
