package WWW::Search::NCBIPubMed;
use feature ':5.10';

=head1 NAME

WWW::Search::NCBIPubMed - Search the NCBI PubMed abstract database.

=head1 SYNOPSIS

 use WWW::Search;
 my $s = new WWW::Search ('NCBIPubMed');
 $s->native_query( '2312563[PMID]' );
 while (my $r = $s->next_result) {
    print $r->title . "\n";
    print $r->description . "\n";
 }

=head1 DESCRIPTION

WWW::Search::NCBIPubMed provides a (maintained) WWW::Search backend for searching the
NCBI/PubMed abstracts database.

=head1 REQUIRES

 L<WWW::Search|WWW::Search>
 L<XML::DOM|XML::DOM>

=cut

use strict;
use warnings;

use parent qw/WWW::Search/;

use Try::Tiny;
use WWW::Search::NCBIPubMed::Result;
use XML::Twig::XPath;
#use Data::Dump qw/dump/;

our $ARTICLES_PER_REQUEST = 20;
our $QUERY_ARTICLE_LIST_URI	= 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmax=500';	# term=ACTG
our $QUERY_ARTICLE_INFO_URI	= 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed';	# &id=12167276&retmode=xml

our $VERSION = '0.00001';
our $debug = 0;

=begin private

=item C<< native_setup_search ( $query, $options ) >>

Sets up the NCBI search using the supplied C<$query> string.

=end private

=cut

sub native_setup_search {
	my ($self, $query, $options) = @_;
	
	$self->user_agent( "WWW::Search::NCBIPubMed/${VERSION} libwww-perl/${LWP::VERSION}" );
	
	my $ua			= $self->user_agent();
	my $url			= $QUERY_ARTICLE_LIST_URI . '&term=' . WWW::Search::escape_query($query);
	my $response	= $ua->get( $url );
	my $success		= $response->is_success;
    $self->{response} = $response;
	return if !$success;
        
    my $twig	= XML::Twig->new();
    $self->{'_xml_twig'}	= $twig;
    my $docres = $twig->parse( $response->content );
    $self->{'_count'} = ($docres->descendants('Count'))[0]->field;
    
    $self->{'_article_ids'} = [ map { $_->field } $docres->descendants('Id') ];
}

=begin private

=item C<< native_retrieve_some >>

Requests search results from NCBI, adding the results to the WWW::Search object's cache.

=end private

=cut

sub native_retrieve_some {
	my $self = shift;
	
	return undef unless scalar (@{ $self->{'_article_ids'} || [] });
	my $ua			= $self->user_agent();
	my $url			= $QUERY_ARTICLE_INFO_URI . '&id=' . join(',', splice(@{ $self->{'_article_ids'} },0,$ARTICLES_PER_REQUEST)) . '&retmode=xml';
	warn 'Fetching URL: ' . $url if $debug;
	my $response	= $ua->get( $url );
    $self->{response} = $response;

	if (! $response->is_success) {
		warn "Request-error" . $response->error_as_HTML();
		return undef;
    }

    my $doc        	= $self->{'_xml_twig'}->parse( $response->content );
    my @articles	= $doc->descendants('PubmedArticle');
    warn (scalar(@articles) . " articles found\n") if $debug;
    my $count		= 0;
    for my $article(@articles) {
        my $id	= ($article->descendants('PMID'))[0]->field;
        warn " ==> ID :$id\n" if $debug;

        # Some articles don't even have the title, sik!
        my $title = ($article->descendants('ArticleTitle'))[0]->field || undef;
        warn "\t$title\n" if $debug;

        my (@authors, @authors_struct, $authors_str);
        my @authornodes	= $article->descendants('Author');

        # Extract author names and provide serveral ways for the users
        # of this module to retrieve them
        foreach my $authornode (@authornodes) {
            my %author_hash = ();
            # Some articles have ForeName, others have FirstName (!)
            for my $a_field(qw/
                ForeName FirstName LastName MiddleName Initials 
            /) {
                my  @a_elements = $authornode->descendants($a_field);
                next if !@a_elements;
                my $item = $a_elements[0]->field;
                next if !defined $item;
                
                $author_hash{$a_field} = $item;
            }
            
            # If we have an author, push him in the arrays
            if ( %author_hash ) {
                push(@authors_struct, \%author_hash);

                push(@authors, join(' ', $author_hash{LastName},$author_hash{Initials}));
            }
        }
        my $author	= join(', ', @authors);
        warn "\t$author\n" if ($debug);
        
        # Get the main dates
        my ($pm_dates, $pm_date_structs, $pm_date_strings);
        for my $dfield( 'PubDate', 'ArticleDate', 'DateCreated' ) {
            my $dnode = ($article->descendants($dfield))[0];
            next if !defined $dnode;
            
            my ($date_struct, $date_string)
                = $self->_process_date( $dnode );
            $pm_date_structs->{lc $dfield} = $date_struct;
            $pm_date_strings->{lc $dfield} = $date_string;
        }

        # We also want the PubMedPubDate entries, which can provide a
        # decent exact date when the PubDate isn't so (and it happens
        # quite often)
        my @PubMedPubDates = $article->descendants('PubMedPubDate');
        for my $PubMedPubDate (@PubMedPubDates) {
            my ($date_struct, $date_string, $pubstatus)
                = $self->_process_date( $PubMedPubDate );
            $pm_date_structs->{"pubmedpubdate_$pubstatus"} = $date_struct;
            $pm_date_strings->{"pubmedpubdate_$pubstatus"} = $date_string;
        }
        
        # ##### Populate result #####
        my $hit = WWW::Search::NCBIPubMed::Result->new();
        
        # Structure with all dates
        $hit->dates_struct($pm_date_structs);
        
        my $source	= '';
        $hit->pubdate( $pm_date_strings->{pubdate} );
        $hit->articledate( $pm_date_strings->{articledate} );
        
        $hit->authors( \@authors_struct );
        $hit->authors_str( $author );
        $hit->journal( $self->get_text_node( $article, 'MedlineTA' ) );
        $hit->doi( $self->_get_doi($article) );
        $hit->volume( $self->get_text_node( $article, 'Volume' ) );
        $hit->issue( $self->get_text_node( $article, 'Issue' ) );
        $hit->page( $self->get_text_node( $article, 'MedlinePgn' ) );
        $hit->title( $title );       
        $hit->pmid( $self->get_text_node( $article, 'PMID' ) );

        my $abstract	= $self->get_text_node( $article, 'AbstractText' );
        $hit->abstract( $abstract ) if ($abstract);
        
        $source	= $hit->journal. ' '
                . ($pm_dates->{PubDate} ? "$pm_dates->{PubDate}; " : '')
                . ($hit->volume ? $hit->volume.' ' : '')
                . ($hit->issue ? '(' . $hit->issue . ') ' : '')
                . ($hit->page ? ':' . $hit->page : '');
        $source	= "(${source})" if ($source);
        warn "\t$source\n" if $debug;
        
        # Public url to the result
        my $url = 'http://www.ncbi.nlm.nih.gov:80/entrez/query.fcgi?cmd=Retrieve&db=PubMed&list_uids=' . $id . '&dopt=Abstract';
        $hit->add_url( $url );
       
        my $desc	= join(' ', grep {$_} ($author, $source));
        $hit->description( $desc );
        push( @{ $self->{'cache'} }, $hit );
        $count++;
        warn "$count : $title\n" if $debug;
    }
    return $count;
}

=begin private

=item C<< get_text_node ( $node, $name )

Returns the text contained in the named descendent of the XML $node.

=end private

=cut

sub get_text_node {
	my ($self, $node, $name) = @_;

    my $text;
    try {
        $text = ($node->descendants($name))[0]->field;
		warn "XML[$name]: $text\n" if $debug;
		return $text;
    } catch {
		warn "XML[$name]: $_" if $debug;
		return undef;
    };
}

sub _get_doi {
	my ($self, $article) = @_;

    # Try ArticleID first
    my @articleids = $article->descendants('ArticleId');
    for my $articleid (@articleids) {
        next if !defined $articleid;

        my $articleid_idtype = $articleid->att('IdType');
        return $articleid->field if $articleid_idtype eq 'doi';
    }
    
    # Attempt ELocationID
    my @elocationids = $article->descendants('ELocationID');
    for my $elocationid (@elocationids) {
        next if !defined $elocationid;

        my $elocationid_eidtype = $elocationid->att('EIdType');
        return $elocationid->field if $elocationid_eidtype eq 'doi';
    }
    
    # No match :-(
    return;
}

sub _process_date {
    my ($self, $node) = @_;
    
    # Get available parts. Date can be of various formats,
    # depeding if it contains all its elements (day, month, ..))
    # Some dates even encomass a period (i.e. Jan-Feb 2009)
    my @parts =  map { $self->get_text_node($node, $_ ) } qw/Year Month Day/;
    
    # We return two string: an hash structure with date parts
    # and a string with those pieces joined into something readable
    # have to parse the date 
    my %date_struct = (
        year => $parts[0], month => $parts[1], day => $parts[2],
    );
    my $date_string = join(' ', grep defined, @parts);

    # Some dates (namely, PubMedPubDate ones) might have a PubStatus
    # attribute which specifies which kind of date it is (entrez,
    # pubmed, medline, ...)
    my $pubstatus = defined $node->att('PubStatus')
        ? lc $node->att('PubStatus') : undef;
    
    return \%date_struct, $date_string, $pubstatus;
}

1;

__END__

=head1 SEE ALSO

L<http://www.ncbi.nlm.nih.gov:80/entrez/query/static/overview.html>
L<http://eutils.ncbi.nlm.nih.gov/entrez/query/static/esearch_help.html>
L<http://eutils.ncbi.nlm.nih.gov/entrez/query/static/efetchlit_help.html>

=head1 LICENSE

This
program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 AUTHOR

Michele Beltrame  C<< <mb@italpro.net> >>

Based on L< WWW::Search::PubMed> by Gregory Todd Williams

=cut

