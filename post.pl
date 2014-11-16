#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Net::Twitter::Lite::WithAPIv1_1;
use Date::Manip;
use URI::Escape;
use Encode;
use Tumblr::API;
use Mango;
use Crypt::CBC;
use MIME::Base64;

Date_Init("TZ=JST");

# Crypt::CBCのコンストラクタ。
my $cipher = Crypt::CBC->new(
	# secret
);

# twitter
my $consumer_key ="***";
my $consumer_key_secret = "***";

my $twit = Net::Twitter::Lite::WithAPIv1_1->new(
	consumer_key    => $consumer_key,
	consumer_secret => $consumer_key_secret,
	ssl => 1
);

# Tumblr.
my $tb_consumer_key = '***';
my $tb_consumer_secret = '***';


my $tb = Tumblr::API->new(
	consumer_key    => $tb_consumer_key,
	consumer_secret     => $tb_consumer_secret,
);

my $doc;
my $mango = Mango->new('mongodb://localhost:***');
my $collection = $mango->db('xxx')->collection('xxx')->find;

while (my $elem = $collection->next) {

	eval{ #あとでなんとかする
		#出力対象タッシュタグ
		my $target = $elem->{target};
		my $user_id = $elem->{user_id};

		#取得開始起点になるID
		my $id_str = $elem->{since_id};

		#twitter
		my $d_access_token =  $elem->{tw_access_token};
		my $d_access_token_secret = $elem->{tw_access_token_secret};
		my $access_token = $cipher->decrypt(MIME::Base64::decode_base64($d_access_token));
		my $access_token_secret = $cipher->decrypt(MIME::Base64::decode_base64($d_access_token_secret));

		$twit->access_token($access_token);
		$twit->access_token_secret($access_token_secret);

		#Tumblr
		my $d_tb_access_token =  $elem->{tb_access_token};
		my $d_tb_access_token_secret = $elem->{tb_access_token_secret};
		my $tb_access_token = $cipher->decrypt(MIME::Base64::decode_base64($d_tb_access_token));
		my $tb_access_token_secret = $cipher->decrypt(MIME::Base64::decode_base64($d_tb_access_token_secret));

		$tb->{token} = $tb_access_token;
		$tb->{token_secret} = $tb_access_token_secret;
		$tb->{base_hostname} = $elem->{base_hostname};

		my $array = "";

		$array = $twit->user_timeline({count => 100,
				include_entities => 'true',
				since_id  => $id_str
			});


		my @post_array=();
		my $counter = 0;
		foreach my $hash (@$array){

			if($counter == 0){
				$mango->db('xxx')->collection('xxx')
				->update({user_id => $user_id}, {'$set'=> {since_id => $hash->{id_str}}});
				$counter = 1;
			}

			#since_idより古いツイートは読まない
			if($id_str eq $hash->{id_str}) {
				last;
			}

			foreach my $hashtag (@{$hash->{entities}{hashtags}}) {
				my $hashtag_text = $hashtag->{text};
				if($hashtag_text eq $target) {
					my $date = ParseDate($hash->{'created_at'});
					my $text = $hash->{'text'};
					my $tag = "#".$hashtag_text;
					$text =~ s/$tag//;

					foreach my $url (@{$hash->{entities}{urls}}) {
						my $tco_url = $url->{url};
						my $long_url = $url->{expanded_url};
						$text =~ s/$tco_url/$long_url/;
					}
					#my $post_text = utf8::encode($text);
					#$post_text = decode_utf8($post_text);
					my %temp_hash = ();
					$temp_hash{body} = $text;
					$temp_hash{title} = UnixDate($date,"%Y/%m/%d %H:%M");

					unshift (@post_array, \%temp_hash);
					last;
				}
			}

		}

		foreach my $entry (@post_array){
			my %post_entry = %$entry;
			$tb->post(
				'text',
				{body => $post_entry{body} },
				{title=> $post_entry{title}},
			);
			sleep 5;
		}
	};

}
