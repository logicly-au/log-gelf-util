use strict;
use Test::More 0.98;
use Test::Exception;
use Test::Warnings 0.005 qw(warning);

use Log::GELF::Util qw(validate_message);

throws_ok{
    my %msg = validate_message();
}
qr/Mandatory parameters '(?:host|short_message)', '(?:host|short_message)' missing.*/,
'mandatory parameters missing';

throws_ok{
    my %msg = validate_message(
        version        => '1.x',
        host           => 1,
        short_message  => 1,
    );
}
qr/The 'version' parameter \("1\.x"\).*/,
'version check';

throws_ok{
    my %msg = validate_message(
        host           => 1,
        short_message  => 1,
        level          => 'x',
    );
}
qr/The 'level' parameter \("x"\).*/,
'level check';

throws_ok{
    my %msg = validate_message(
        host           => 1,
        short_message  => 1,
        bad            => 'to the bone.',
    );
}
qr/invalid field 'bad'.*/,
'bad field check';

like( warning {
    my %msg = validate_message(
        host           => 1,
        short_message  => 1,
        facility       => 1,
    );
},
qr/^facility is deprecated.*/,
'facility deprecated');

like( warning {
    my %msg = validate_message(
        host           => 1,
        short_message  => 1,
        file           => 1,
    );
},
qr/^file is deprecated.*/,
'file deprecated');

my %msg;
lives_ok{
    %msg = validate_message(
        host           => 1,
        short_message  => 1,
    );
}
'default version';

my $time = time;
is($msg{version}, '1.1', 'correct default version');
like($msg{timestamp}, qr/\d+\.\d+/, 'default timestamp');

done_testing(10);
