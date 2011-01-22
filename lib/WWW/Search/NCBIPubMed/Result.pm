package WWW::Search::NCBIPubMed::Result;

=head1 NAME

WWW::Search::NCBIPubMed::Result - NCBI Search Result

=head1 SYNOPSIS

 use WWW::Search;
 my $s = new WWW::Search ('PubMed');
 $s->native_query( 'ACGT' );
 while (my $result = $s->next_result) {
  print $result->title . "\n";
  print $result->description . "\n";
  print $result->pmid . "\n";
  print $result->abstract . "\n";
 }

=head1 DESCRIPTION

WWW::Search::PubMed::Result objects represent query results returned
from a WWW::Search::PubMed search. See L<WWW::Search:PubMed> for more
information.

=head1 VERSION

This document describes WWW::Search::PubMed version 1.004,
released 31 October 2007.

=head1 REQUIRES

 L<WWW::Search::PubMed|WWW::Search::PubMed>

=head1 METHODS

=over 4

=cut

our($VERSION)	= '1.004';

use strict;
use warnings;

use parent qw(WWW::Search::Result);


=item C<< pmid >>

The article PMID.

=cut

sub pmid { return shift->_elem('pmid', @_); }


=item C<< abstract >>

The article abstract.

=cut

sub abstract { return shift->_elem('abstract', @_); }


=item C<< dates_struct >>

Returns an hashref containing all dates we found. It'll likely be
like this example, or a subset of it:

{
    articledate                 => { day => 24, month => 2, year => 2009 },
    datecreated                 => { day => 24, month => 2, year => 2009 },
    pubdate                     => { day => 24, month => "Feb", year => 2009 },
    pubmedpubdate_accepted      => { day => 27, month => 1, year => 2009 },
    pubmedpubdate_aheadofprint  => { day => 24, month => 2, year => 2009 },
    pubmedpubdate_entrez        => { day => 25, month => 2, year => 2009 },
    pubmedpubdate_medline       => { day => 25, month => 2, year => 2009 },
    pubmedpubdate_pubmed        => { day => 25, month => 2, year => 2009 },
    pubmedpubdate_received      => { day => 9, month => 11, year => 2008 },
}

=cut

sub dates_struct { return shift->_elem('dates_struct', @_); }


=item C<< pubdate >>

The article's publication date ("YYYY Mon DD" or "YYYY Mon" or
"YYY Mon1-Mon2" or "YYYY" or ...). Should be formatted like it is when
surfing PubMed web site.
Please note that this date might not be available, so you'd better
(also) work with the values of date_struct to get something more reliable.

=cut

sub pubdate { return shift->_elem('pubdate', @_); }


=item C<< articledate >>

The article's date ("YYYY Mon DD" or "YYYY Mon" or "YYYY").
This is a date that PubMed assigns to the article, which could be useful
when the pubdate (date) is partial.

=cut

sub articledate { return shift->_elem('articledate', @_); }


=item C<< articledate_struct >>

Returns an hash reference containing all the elements of the article date (year,
month, day)
This is a date that PubMed assigns to the article, which could be useful
when the pubdate (date) is partial.

=cut

sub authors { return shift->_elem('authors', @_); }


=item C<< authors_str >>

Returns a string containing authors structured such as this:

    Douglas R., Smith K.,

=cut

sub authors_str { return shift->_elem('authors_str', @_); }


=item C<< journal >>

the journal the article belongs to

=cut

sub journal { return shift->_elem('journal', @_); }


=item C<< doi >>

the doi ID (see I<http://dx.doi.org>) for the full article, if available

=cut

sub doi { return shift->_elem('doi', @_); }

sub volume { return shift->_elem('volume', @_); }
sub issue { return shift->_elem('issue', @_); }
sub page { return shift->_elem('page', @_); }

1;

__END__

=back

=head1 LICENSE

This
program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 AUTHOR

Michele Beltrame  C<< <mb@italpro.net> >>

Based on L< WWW::Search::NCBI::PubMed> by Gregory Todd Williams

=cut
