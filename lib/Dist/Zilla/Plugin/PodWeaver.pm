package Dist::Zilla::Plugin::PodWeaver;
# ABSTRACT: weave your Pod together from configuration and Dist::Zilla
use Moose;
use Moose::Autobox;
use List::MoreUtils qw(any);
use Pod::Weaver 3.100710; # logging with proxies
with 'Dist::Zilla::Role::FileMunger';

use namespace::autoclean;

use PPI;
use Pod::Elemental;
use Pod::Elemental::Transformer::Pod5;
use Pod::Elemental::Transformer::Nester;
use Pod::Elemental::Selectors -all;
use Pod::Weaver::Config::Assembler;

=head1 DESCRIPTION

[PodWeaver] is the bridge between L<Dist::Zilla> and L<Pod::Weaver>.  It rips
apart your kinda-Pod and reconstructs it as boring old real Pod.

=head1 CONFIGURATION

If the C<config_plugin> attribute is given, it will be treated like a
Pod::Weaver section heading.  For example, C<@Default> could be given.

Otherwise, if a file matching C<./weaver.*> exists, Pod::Weaver will be told to
look for configuration in the current directory.

Otherwise, it will use the default configuration.

=method weaver

This method returns the Pod::Weaver object to be used.  The current
implementation builds a new weaver on each invocation, because one or two core
Pod::Weaver plugins cannot be trusted to handle multiple documents per plugin
instance.  In the future, when that is fixed, this may become an accessor of an
attribute with a builder.  Until this is clearer, use caution when modifying
this method in subclasses.

=cut

sub weaver {
  my ($self) = @_;

  my @files = glob('weaver.*');

  my $arg = { root_config => { logger => $self->logger } };

  if ($self->config_plugin) {
    my $assembler = Pod::Weaver::Config::Assembler->new;

    my $root = $assembler->section_class->new({ name => '_' });
    $assembler->sequence->add_section($root);

    $assembler->change_section( $self->config_plugin );
    $assembler->end_section;

    return Pod::Weaver->new_from_config_sequence($assembler->sequence, $arg);
  } elsif (@files) {
    return Pod::Weaver->new_from_config($arg);
  } else {
    return Pod::Weaver->new_with_default_config($arg);
  }
}

has config_plugin => (
  is  => 'ro',
  isa => 'Str',
);

sub munge_file {
  my ($self, $file) = @_;

  $self->log_debug([ 'weaving pod in %s', $file->name ]);

  return
    unless $file->name =~ /\.(?:pm|pod)$/i
    and ($file->name !~ m{/} or $file->name =~ m{^lib/});

  $self->munge_pod($file);
  return;
}

sub munge_perl_string {
  my ($self, $doc, $arg) = @_;

  my $weaver  = $self->weaver;
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
      zilla    => $self->zilla,
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
