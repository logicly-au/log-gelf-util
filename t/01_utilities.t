use strict;
use Test::More 0.98;
use Test::Exception;
use Test::Warnings 0.005 qw(warning);

use Log::GELF::Util;

throws_ok{
    my %msg = Log::GELF::Util::parse_size();
}
qr/0 parameters were passed.*/,
'parse_size mandatory parameters missing';

throws_ok{
    my %msg = Log::GELF::Util::parse_size({});
}
qr/Parameter #1.*/,
'parse_size wrong type';

throws_ok{
    my %msg = Log::GELF::Util::parse_size(-1);
}
qr/Parameter #1.*/,
'parse_size invalid numeric value';

throws_ok{
    my %msg = Log::GELF::Util::parse_size('wrong');
}
qr/Parameter #1.*/,
'parse_size invalid string value';

my $size;
lives_ok{
    $size = Log::GELF::Util::parse_size(1);
}
'numeric level';
is($size, 1, 'correct numeric size');

lives_ok{
    $size = Log::GELF::Util::parse_size('lan');
}
'string lan level';
is($size, 8152, 'correct numeric size');

lives_ok{
    $size = Log::GELF::Util::parse_size('wan');
}
'string wan level';
is($size, 1420, 'correct numeric size');

throws_ok{
   Log::GELF::Util::parse_level();
}
qr/0 parameters were passed.*/,
'parse_level mandatory parameters missing';

throws_ok{
   Log::GELF::Util::parse_level({});
}
qr/Parameter #1.*/,
'parse_level wrong type';

throws_ok{
   Log::GELF::Util::parse_level(-1);
}
qr/invalid log level.*/,
'parse_level invalid numeric value';

throws_ok{
   Log::GELF::Util::parse_level(8);
}
qr/invalid log level.*/,
'parse_level invalid numeric value - too big';

throws_ok{
    Log::GELF::Util::parse_level('wrong');
}
qr/invalid log level.*/,
'parse_level invalid string value';

my $level;
lives_ok{
    $level = Log::GELF::Util::parse_level(0);
}
'correct numeric level';
is($level, 0, 'correct numeric level min');

lives_ok{
    $level = Log::GELF::Util::parse_level(7);
}
'correct numeric level';
is($level, 7, 'correct numeric level max');

my $level_no = 0;
foreach my $lvl_name (
    qw(
        emerg
        alert
        crit
        err
        warn
        notice
        info
        debug
    )
) {
    lives_ok{
        $level = Log::GELF::Util::parse_level($lvl_name);
    }
    "level $lvl_name ok";
    
    is($level, $level_no++, "level $lvl_name correct value");
}

$level_no = 0;
foreach my $lvl_name (
    qw(
        emergency
        alert
        critical
        error
        warning
        notice
        information
        debug
    )
) {
    lives_ok{
        $level = Log::GELF::Util::parse_level($lvl_name);
    }
    "level long $lvl_name ok";
    
    is($level, $level_no++, "level long $lvl_name correct value");
}

done_testing();
