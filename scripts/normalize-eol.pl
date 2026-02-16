#!/bin/sh
# Shell/Perl bootstrap: shell runs this line, exec-ing Perl with -x to skip
# the shell preamble.  PERL_BADLANG=0 is set only when $MSYSTEM is defined
# (MSYS2/Git Bash) to suppress "Setting locale failed" warnings caused by
# LANG=en_US.UTF-8 not being recognized by Perl's C runtime on Windows.
# On Linux/macOS, locale warnings are preserved.
exec env ${MSYSTEM:+PERL_BADLANG=0} perl -x "$0" "$@"
#!perl
use strict;
use warnings;

=head1 NAME

normalize-eol.pl - Normalize line endings for one or more files

=head1 SYNOPSIS

  perl normalize-eol.pl <CRLF|LF> <file> [file ...]
  perl normalize-eol.pl --help

=head1 DESCRIPTION

Normalizes each file by first canonicalizing all newlines to LF,
then rewriting to the requested target EOL:

  CRLF  => \r\n
  LF    => \n

=cut

sub usage {
  print <<'USAGE';
Usage:
  perl normalize-eol.pl <CRLF|LF> <file> [file ...]

Examples:
  perl normalize-eol.pl CRLF README.md
  perl normalize-eol.pl LF a.txt b.txt
USAGE
}

if (!@ARGV || grep { $_ eq '--help' || $_ eq '-h' } @ARGV) {
  usage();
  exit 0;
}

my $target = shift @ARGV;
if (!defined $target || ($target ne 'CRLF' && $target ne 'LF')) {
  die "error: first argument must be CRLF or LF\n";
}
if (!@ARGV) {
  die "error: provide at least one file path\n";
}

for my $path (@ARGV) {
  if (!-e $path) {
    die "error: path does not exist: $path\n";
  }
  if (-d $path) {
    die "error: path is a directory: $path\n";
  }

  open my $in, '<:raw', $path or die "error: failed to open '$path': $!\n";
  local $/;
  my $s = <$in>;
  close $in;
  $s = '' unless defined $s;

  $s =~ s/\r\n/\n/g;
  $s =~ s/\r/\n/g;
  if ($target eq 'CRLF') {
    $s =~ s/\n/\r\n/g;
  }

  open my $out, '>:raw', $path or die "error: failed to write '$path': $!\n";
  print {$out} $s or die "error: failed to write data for '$path': $!\n";
  close $out or die "error: failed to close '$path': $!\n";
}

exit 0;
