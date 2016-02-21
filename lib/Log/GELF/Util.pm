package Log::GELF::Util;
use 5.010;
use strict;
use warnings;

our $VERSION = "0.01";

use Params::Validate qw(validate SCALAR ARRAYREF HASHREF);
use Time::HiRes qw(time);
use Sys::Syslog qw(:macros);
use JSON::MaybeXS qw(encode_json);
use IO::Compress::Gzip qw(gzip $GzipError);
use Math::Random::MT qw(irand);

our $GELF_MSG_MAGIC        = pack('C*', 0x1e, 0x0f);
our @GELF_MSG_MAGIC_SPEC   = (0, 2);
our @GELF_MSG_ID_SPEC      = (2, 8);
our @GELF_MSG_SEQ_NO_SPEC  = (10,1);
our @GELF_MSG_SEQ_CNT_SPEC = (11,1);
our @GELF_MSG_SPEC         = (12);

our %LEVEL_NAME_TO_NUMBER  = (
    emerg  => LOG_EMERG,
    alert  => LOG_ALERT,
    crit   => LOG_CRIT,
    err    => LOG_ERR,
    warn   => LOG_WARNING,
    notice => LOG_NOTICE,
    info   => LOG_INFO,
    debug  => LOG_DEBUG,
);

my $ln = '$(' .
    join '|', (keys %LEVEL_NAME_TO_NUMBER) .
    ')\w*$';

our $LEVEL_NAME_REGEX = qr/$ln/i;

sub validate_message {
    my %p = validate(
        @_,
        {
            version       => { regex => qr/^\d+$/ },
            host          => { type  => SCALAR },
            short_message => { type  => SCALAR },
            full_message  => { type  => SCALAR, optional => 1 },
            timestamp     => { type  => SCALAR, default  => time },
            level         => {
                default => 1,
                regex   => qr/^(?:0|1|2|3|4|5|6|7)$/,
            },
            facility      => {
                regex     => qr/^\d+$/,
                callbacks => {           # ... and smaller than 90
                    deprecated => sub { warn "level is deprecated, send as additional field instead" },
                },
            },
            file          => {
                type      => SCALAR,
                callbacks => {
                    deprecated => sub { warn "level is deprecated, send as additional field instead" },
                },
            },
        },
    );
}

sub encode {
    my %p = validate(
        @_,
        {
            message => {
                type => HASHREF,
                callbacks => {
                    validate_message => \&validate_message,
                },
            },
        },
    );

    return encode_json($p{message});
}

sub compress {
    my %p = validate(
        @_,
        {
            message => { type => SCALAR },
        },
    );

    my $msgz;
    gzip \$p{message} => \$msgz
      or die "gzip failed: $GzipError";

    return $msgz;
}

sub enchunk {
    my %p = validate(
        @_,
        {
            size =>    { regex => qr/^\d+$/ },
            message => { type => SCALAR },
        },
    );

    if ( $p{size}
         && length $p{message} > $p{size}
    ) {
        my @chunks;
        while (length $p{message}) {
            push @chunks, substr $p{message}, 0, $p{size}, '';
        }

        my $n_chunks = scalar @chunks;
        die 'Message too big' if $n_chunks > 128;

        my $magic          = pack('C*', 0x1e,0x0f); # Chunked GELF magic bytes
        my $message_id     = pack('L*', irand(),irand());
        my $sequence_count = pack('C*', $n_chunks);

        my @chunks_w_header;
        my $sequence_number = 0;
        foreach my $chunk (@chunks) {
           push @chunks_w_header,
              $magic
              . $message_id
              . pack('C*',$sequence_number++)
              . $sequence_count
              . $chunk;
        }

        return @chunks_w_header;
    }
    else {
         return ($p{message});
    }
}

sub is_chunked {
    my %p = validate(
        @_,
        {
            chunk => { type => SCALAR },
        },
    );

    return $GELF_MSG_MAGIC eq substr $p{chunk}, @GELF_MSG_MAGIC_SPEC;
}

sub decode_chunk {
    my %p = validate(
        @_,
        {
            encoded_chunk => { type => SCALAR },
        },
    );

    my $msg_magic   = substr $p{encoded_chunk}, @GELF_MSG_MAGIC_SPEC;

    if ( $msg_magic eq $GELF_MSG_MAGIC ) {
        return {
            id              => unpack('LL', substr $p{encoded_chunk}, @GELF_MSG_ID_SPEC),
            sequence_number => unpack('C',  substr $p{encoded_chunk}, @GELF_MSG_SEQ_NO_SPEC),
            sequence_count  => unpack('C',  substr $p{encoded_chunk}, @GELF_MSG_SEQ_CNT_SPEC),
            chunk           => substr $p{encoded_chunk}, @GELF_MSG_SPEC,
        };
    }
    else {
        die "message not chunked";
    }
}

sub parse_level {
    my %p = validate(
        @_,
        {
            level => { type => SCALAR },
        }
    );

    if ( $p{level} =~ $LEVEL_NAME_REGEX ) {
        return %LEVEL_NAME_TO_NUMBER{$1};
    }
    elsif ( $p{level} =~ /^(?:0|1|2|3|4|5|6|7)$/ ) {
        return $p{level};
    }
    else {
        die "invalid log level";
    }
}

sub parse_size {
    my %p = validate(
        @_,
        {
            size => { regex => qr/^(lan|wan|\d+)$/i },
        },
    );

    # These default values below were determined by
    # examining the code for Graylog's implementation. See
    #  https://github.com/Graylog2/gelf-rb/blob/master/lib/gelf/notifier.rb#L62
    # I believe these are determined by likely MTU defaults
    #  and possible heasers like so...
    # WAN: 1500 - 8 b (UDP header) - 60 b (max IP header) - 12 b (chunking header) = 1420 b
    # LAN: 8192 - 8 b (UDP header) - 20 b (min IP header) - 12 b (chunking header) = 8152 b
    # Note that based on my calculation the Graylog LAN
    #  default may be 2 bytes too big (8154)
    # See http://stackoverflow.com/questions/14993000/the-most-reliable-and-efficient-udp-packet-size
    # For some discussion. I don't think this is an exact science!

    if ( lc($1) eq 'wan' ) {
        return 1420;
    }
    elsif ( lc($1) eq 'lan' ) {
        return 8152;
    }
    else {
        return $1;
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Log::GELF::Util - It's new $module

=head1 SYNOPSIS

    use Log::GELF::Util;

=head1 DESCRIPTION

Log::GELF::Util is ...

=head1 LICENSE

Copyright (C) Adam Clarke.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Adam Clarke E<lt>adam.clarke@strategicdata.com.auE<gt>

=cut

