package Dist::Zilla::Plugin::PodWeaver;
# ABSTRACT: weave your Pod together from configuration and Dist::Zilla

use Moose;
use Pod::Weaver 3.100710; # logging with proxies
with 'Dist::Zilla::Role::FileMunger',
     'Dist::Zilla::Role::FileFinderUser' => {
       default_finders => [ ':InstallModules', ':PerlExecFiles' ],
     };

# BEGIN BOILERPLATE
use v5.20.0;
use warnings;
use utf8;
no feature 'switch';
use experimental qw(postderef postderef_qq); # This experiment gets mainlined.
# END BOILERPLATE

use namespace::autoclean;

=head1 DESCRIPTION

[PodWeaver] is the bridge between L<Dist::Zilla> and L<Pod::Weaver>.  It rips
apart your kinda-Pod and reconstructs it as boring old real Pod.

=head1 CONFIGURATION

If the C<config_plugin> attribute is given, it will be treated like a
Pod::Weaver section heading.  For example, C<@Default> could be given.  It may
be given multiple times.

Otherwise, if a file matching C<./weaver.*> exists, Pod::Weaver will be told to
look for configuration in the current directory.

Otherwise, it will use the default configuration.

=attr finder

[PodWeaver] is a L<Dist::Zilla::Role::FileFinderUser>.  The L<FileFinder> given
for its C<finder> attribute is used to decide which files to munge.  By
default, it will munge:

=for :list
* C<:InstallModules>
* C<:ExecFiles>

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

  my $root = $self->zilla->root->stringify;

  my @files = glob("$root/weaver.*");

  my $arg = {
      root        => $root,
      root_config => { logger => $self->logger },
  };

  if ($self->has_config_plugins) {
    my $assembler = Pod::Weaver::Config::Assembler->new;

    my $root = $assembler->section_class->new({ name => '_' });
    $assembler->sequence->add_section($root);

    for my $header ($self->config_plugins) {
      $assembler->change_section($header);
      $assembler->end_section;
    }

    return Pod::Weaver->new_from_config_sequence($assembler->sequence, $arg);
  } elsif (@files) {
    return Pod::Weaver->new_from_config(
      { root   => $root },
      { root_config => { logger => $self->logger } },
    );
  } else {
    return Pod::Weaver->new_with_default_config($arg);
  }
}


sub mvp_aliases { return { config_plugin => 'config_plugins' } }
sub mvp_multivalue_args { qw(config_plugins) }

has config_plugins => (
  isa => 'ArrayRef[Str]',
  traits  => [ 'Array' ],
  default => sub {  []  },
  handles => {
    config_plugins     => 'elements',
    has_config_plugins => 'count',
  },
);

around dump_config => sub
{
  my ($orig, $self) = @_;
  my $config = $self->$orig;

  my $our = {
    $self->has_config_plugins
      ? ( config_plugins => [ $self->config_plugins ] )
      : (),
    finder => $self->finder,
  };

  $our->{plugins} = [];
  for my $plugin ($self->weaver->plugins->@*) {
    push $our->{plugins}->@*, {
      class   => $plugin->meta->name,
      name    => $plugin->plugin_name,
      version => $plugin->VERSION,
    };
  }

  $config->{'' . __PACKAGE__} = $our;

  return $config;
};

sub munge_files {
  my ($self) = @_;

  require PPI;
  require Pod::Weaver;
  require Pod::Weaver::Config::Assembler;

  $self->munge_file($_) for $self->found_files->@*;
}

sub munge_file {
  my ($self, $file) = @_;

  $self->log_debug([ 'weaving pod in %s', $file->name ]);

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

  my @authors = $self->zilla->authors;
  @authors = $authors[0]->@* if @authors == 1 && ref $authors[0];

  my $new_content = $self->munge_perl_string(
    $file->content,
    {
      zilla    => scalar $self->zilla,
      filename => scalar $file->name,
      version  => scalar $self->zilla->version,
      license  => scalar $self->zilla->license,
      authors  => \@authors,
      distmeta => scalar $self->zilla->distmeta,
    },
  );

  $file->content($new_content);

  return;
}

with 'Pod::Elemental::PerlMunger' => { -version => 0.100000 };

__PACKAGE__->meta->make_immutable;
no Moose;
1;
