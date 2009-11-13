package Dist::Zilla::Plugin::PodWeaver;
# ABSTRACT: do horrible things to POD, producing better docs
use Moose;
use Moose::Autobox;
use List::MoreUtils qw(any);
use Pod::Weaver 3.093001; # @Default
with 'Dist::Zilla::Role::FileMunger';

use namespace::autoclean;

use PPI;
use Pod::Elemental;
use Pod::Elemental::Transformer::Pod5;
use Pod::Elemental::Transformer::Nester;
use Pod::Elemental::Selectors -all;
use Pod::Weaver::Config::Assembler;

=head1 WARNING

This code is really, really sketchy.  It's crude and brutal and will probably
break whatever it is you were trying to do.

Eventually, this code will be really awesome.  I hope.  It will probably
provide an interface to something more cool and sophisticated.  Until then,
don't expect it to do anything but bring sorrow to you and your people.

=head1 DESCRIPTION

PodWeaver is a work in progress, which rips apart your kinda-POD and
reconstructs it as boring old real POD.

=head1 CONFIGURATION

If the C<config_plugin> attribute is given, it will be treated like a
Pod::Weaver section heading.  For example, C<@Default> could be given.

Otherwise, if a file matching C<./weaver.*> exists, Pod::Weaver will be told to
look for configuration in the current directory.

Otherwise, it will use the default configuration.

=cut

sub _weaver {
  my ($self) = @_;

  my @files = glob('weaver.*');

  if ($self->config_plugin) {
    my $assembler = Pod::Weaver::Config::Assembler->new;

    my $root = $assembler->section_class->new({ name => '_' });
    $assembler->sequence->add_section($root);

    $assembler->change_section( $self->config_plugin );
    $assembler->end_section;

    return Pod::Weaver->new_from_config_sequence($assembler->sequence);
  } elsif (@files) {
    return Pod::Weaver->new_from_config;
  } else {
    return Pod::Weaver->new_with_default_config;
  }
}

has config_plugin => (
  is  => 'ro',
  isa => 'Str',
);

sub munge_file {
  my ($self, $file) = @_;

  return
    unless $file->name =~ /\.(?:pm|pod)$/i
    and ($file->name !~ m{/} or $file->name =~ m{^lib/});

  $self->munge_pod($file);
  return;
}

sub munge_perl_string {
  my ($self, $doc, $arg) = @_;

  my $weaver  = $self->_weaver;
  my $new_doc = $weaver->weave_document({
    %$arg,
    pod_document => $doc->{pod},
    ppi_document => $doc->{ppi},
  });

  return {
    pod => $new_doc,
    ppi => $doc->{ppi},
  }
}

sub munge_pod {
  my ($self, $file) = @_;

  my $content     = $file->content;
  my $new_content = $self->munge_perl_string(
    $file->content,
    {
      filename => $file->name,
      version  => $self->zilla->version,
      license  => $self->zilla->license,
      authors  => $self->zilla->authors,
    },
  );

  $file->content($new_content);

  return;
}

with 'Pod::Elemental::PerlMunger';

__PACKAGE__->meta->make_immutable;
no Moose;
1;
