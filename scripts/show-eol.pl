#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

show-eol.pl - Report line-ending style for one or more files

=head1 SYNOPSIS

  perl show-eol.pl <file> [file ...]
  perl show-eol.pl --help

=head1 DESCRIPTION

Prints one row per file with:

  Path  EolType  CRLF  LF  CR

EolType is one of: CRLF, LF, CR, Mixed, None.

=cut

sub usage {
  print <<'USAGE';
Usage:
  perl show-eol.pl <file> [file ...]

Examples:
  perl show-eol.pl README.md
  perl show-eol.pl a.txt b.txt
USAGE
}

if (!@ARGV || grep { $_ eq '--help' || $_ eq '-h' } @ARGV) {
  usage();
  exit 0;
}

print join("\t", qw(Path EolType CRLF LF CR)), "\n";

for my $path (@ARGV) {
  if (!-e $path) {
    die "error: path does not exist: $path\n";
  }
  if (-d $path) {
    die "error: path is a directory: $path\n";
  }

  open my $fh, '<:raw', $path or die "error: failed to open '$path': $!\n";
  local $/;
  my $s = <$fh>;
  close $fh;
  $s = '' unless defined $s;

  my $crlf = () = ($s =~ /\r\n/g);
  (my $tmp = $s) =~ s/\r\n//g;
  my $cr = () = ($tmp =~ /\r/g);
  my $lf = () = ($tmp =~ /\n/g);

  my $type = 'Mixed';
  if ($crlf == 0 && $lf == 0 && $cr == 0) {
    $type = 'None';
  } elsif ($crlf > 0 && $lf == 0 && $cr == 0) {
    $type = 'CRLF';
  } elsif ($lf > 0 && $crlf == 0 && $cr == 0) {
    $type = 'LF';
  } elsif ($cr > 0 && $crlf == 0 && $lf == 0) {
    $type = 'CR';
  }

  print join("\t", $path, $type, $crlf, $lf, $cr), "\n";
}

exit 0;
