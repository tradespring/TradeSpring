use inc::Module::Install;
name 'TradeSpring';
all_from 'lib/TradeSpring.pm';
readme_from 'lib/TradeSpring.pm';
build_requires 'Test::More';
extra_tests;

tests 't/*.t t/*/*.t';

requires 'methods'                 => '0.10';
requires 'Term::ANSIScreen';
requires 'MooseX::Log::Log4perl';
requires 'Log::Log4perl';
requires 'Net::Address::IP::Local';
requires 'MooseX::SimpleConfig';
requires 'MooseX::Getopt';
requires 'MooseX::Alien';
requires 'Test::File::Contents';
requires 'UNIVERSAL::require';
requires 'Number::Extreme';
requires 'MooseX::ClassAttribute';
requires 'DateTime::Format::Strptime';
requires 'List::MoreUtils';
requires 'List::AllUtils';
requires 'UNIVERSAL::require';
requires 'Graph';
requires 'Data::Walk';
requires 'YAML::Syck';
requires 'FSA::Rules'      => '0.32';
requires 'Config::GitLike' => '1.08';
requires 'Set::IntSpan';
requires 'Math::Random::MT';
requires 'Path::Class';
requires 'Statistics::Basic';

requires 'Finance::Instrument';

test_requires 'Test::Log::Log4perl';
test_requires 'Test::Deep';

WriteAll;
