use Test::More;

use_ok('WWW::Search::NCBIPubMed');

my $ws = WWW::Search->new('NCBIPubMed');
$ws->maximum_to_retrieve( 2 ); 
$ws->native_query('21254285[PMID]');
ok( $ws->response->is_success );

my $wr = $ws->next_result;
ok( $ws->response->is_success );
ok( $wr ); # It should be found

use Data::Dump qw/dump/;
print $wr->title;
print dump $wr->dates_struct;

done_testing();
