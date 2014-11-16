#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Encode;
use Mango;
use Mango::BSON 'bson_oid';
use Crypt::CBC;
use Tumblr::API;
use Net::Twitter::Lite::WithAPIv1_1;
use Mojolicious::Lite;
use MIME::Base64;

helper mango  => sub { state $mango = Mango->new("mongodb://localhost:***") };
helper pastes => sub { shift->mango->db('xxx')->collection('xxx') };

# hypnotoad設定
app->config(hypnotoad => {
	listen => ['http://*:***'],
        user => '***', #hypnotoadの実行ユーザ
        group => '***', #hypnotoadの実行グループ
});

# Tumblr.
my $tb_consumer_key = 'xxx';
my $tb_consumer_secret = 'xxx';

my $tb = Tumblr::API->new(
	consumer_key    => $tb_consumer_key,
	consumer_secret     => $tb_consumer_secret,
);

# twitter
my $consumer_key ="xxx";
my $consumer_key_secret = "xxx";

my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
	consumer_key    => $consumer_key,
	consumer_secret => $consumer_key_secret,
	ssl => 1
);

# Crypt::CBCのコンストラクタ。
my $cipher = Crypt::CBC->new(
	# secret
);

get '/' => sub {
	my $self = shift;
} => 'index';


get '/auth_twitter' => sub {
	my $self = shift;

	my $mode = $self->param('mode') || "";
	$self->session( delete => $mode );

	my $cb_url = $self->url_for('auth_cb_twitter')->to_abs->scheme('https');
	my $url = $nt->get_authorization_url( callback => $cb_url );

	$self->session( token_twitter => $nt->request_token );
	$self->session( token_secret_twitter => $nt->request_token_secret );

	$self->redirect_to( $url );
} => 'auth_twitter';

get '/auth_cb_twitter' => sub {
	my $self = shift;
	my $verifier = $self->param('oauth_verifier') || '';
	my $token = $self->session('token_twitter') || '';
	my $token_secret = $self->session('token_secret_twitter') || '';

	$nt->request_token( $token );
	$nt->request_token_secret( $token_secret );

	# Access token取得
	my ($access_token, $access_token_secret, $user_id, $screen_name)
	= $nt->request_access_token( verifier => $verifier );

	# Sessionに格納
	$self->session( access_token_twitter => $access_token );
	$self->session( access_token_secret_twitter => $access_token_secret );
	$self->session( user_id => $user_id );
	$self->session( screen_name => $screen_name );

	$self->redirect_to( 'form' );

} => 'auth_cb_twitter';

get '/form' => sub {
	my $self = shift;
	my $user_id = $self->session( 'user_id' ) || "";
	return $self->redirect_to( 'index' ) unless ($user_id);

	my $doc = $self->pastes->find_one({user_id => $user_id});
	my $doc_name = $doc->{user_id} || "";
	my $mode = $self->session('delete') || '';

	if($mode eq 'delete'){
		if($doc_name) {
			return $self->render(
				template => 'deleteform',
				screen_name => $self->session('screen_name'),
				base_hostname => $doc->{base_hostname},
				target => $doc->{target},
			);

		}
		else {
			return $self->render(
				template => 'error',
				message  => "指定されたTwitter IDは登録されていません。"
			);
		}
	}
	else {
		if($doc_name) {
			return $self->render(
				template => 'error',
				message  => "指定されたTwitter IDはすでに登録済みです。"
			);
		}
		else {
			return $self->render(
				template => 'regist',
			);
		}
	}

} => 'form';

post '/delete' => sub {
	my $self = shift;
	my $access_token_twitter = $self->session( 'access_token_twitter' ) || "";
	my $access_token_secret_twitter = $self->session( 'access_token_secret_twitter' ) || "";
	return $self->redirect_to( 'index' ) unless ($access_token_twitter && $access_token_secret_twitter);

	$nt->access_token($access_token_twitter);
	$nt->access_token_secret($access_token_secret_twitter);

	my $array = $nt->user_timeline({count => 1});
	my $user_id_str = $array->[0]->{user}->{id_str};
	my $user_id = $self->session( 'user_id' ) || "";
	if( $user_id_str eq $user_id ) {
		$self->pastes->remove({user_id => $user_id_str});
		$self->session( expires => 1 );
		return $self->render(
			template => 'complete',
			type => '登録解除'
		);
	}
	else {
		return $self->redirect_to( 'index' );
	}
} => 'delete';

post '/auth' => sub {
	my $self = shift;

	my $target = $self->param('target') || "";
	my $base_hostname = $self->param('base_hostname') || "";

	return $self->redirect_to( 'index' ) unless ($base_hostname && $target);
	
	my $pattern = '[<>%\$@\'()!\?,！”＃＄％＆’（）＝～｜‘｛＋＊｝＜＞？＿－＾￥＠「；：」、。・]';
	if ($target =~ /${pattern}/ || $base_hostname =~ /${pattern}/){
		return $self->render(
			template => 'error',
			message  => "不正な文字が使用されています。"
		);
	}

	$self->session( target => $target );
	$self->session( base_hostname => $base_hostname );

	my $access_token = $self->session( 'access_token_twitter' ) || '';
	my $access_token_secret = $self->session( 'access_token_secret_twitter' ) || '';
	return $self->redirect_to( 'index' ) unless ($access_token && $access_token_secret);

	my $cb_url = $self->url_for('auth_cb')->to_abs()->scheme('https');
	my $url = $tb->get_authorization_url();

	$self->session( token => $tb->{request_token} );
	$self->session( token_secret => $tb->{request_token_secret} );

	$self->redirect_to( $url );
} => 'auth';

get '/auth_cb' => sub {

	my $self = shift;

	my $token = $self->session('token') || '';
	my $token_secret = $self->session('token_secret') || '';
	my $base_hostname = $self->session('base_hostname') || '';
	my $target = $self->session('target') || '';
	my $verifier = $self->param('oauth_verifier') || '';

	return $self->redirect_to( 'index' ) unless ($token && $token_secret && $base_hostname && $target);

	$tb->{request_token} = $token;
	$tb->{request_token_secret} = $token_secret;

	# Access token取得
	my ($access_token, $access_token_secret) =
		$tb->get_access_token( oauth_verifier => $verifier );

	# 暗号化
	my $s_access_token = $cipher->encrypt($access_token);
	my $s_access_token_secret = $cipher->encrypt($access_token_secret);

	# Twitter側
	my $access_token_twitter = $self->session( 'access_token_twitter' );
	my $access_token_secret_twitter = $self->session( 'access_token_secret_twitter' );
	my $user_id = $self->session( 'user_id' );

	my $doc = $self->pastes->find_one({user_id => $user_id});
	my $doc_name = $doc->{user_id} || "";
	if($doc_name) {
		return $self->render(
			template => 'error',
			message  => "指定されたTwitter IDはすでに登録済みです。"
		);
	}

	# 暗号化
	my $s_access_token_twitter = $cipher->encrypt($access_token_twitter);
	my $s_access_token_secret_twitter = $cipher->encrypt($access_token_secret_twitter);

	$nt->access_token($access_token_twitter);
	$nt->access_token_secret($access_token_secret_twitter);

	my $array = $nt->user_timeline({count => 1});
	my $since_id = $array->[0]->{id_str};
	my $access_tokens  =  {
		tw_access_token => MIME::Base64::encode_base64($s_access_token_twitter),
		tw_access_token_secret => MIME::Base64::encode_base64($s_access_token_secret_twitter),
		tb_access_token => MIME::Base64::encode_base64($s_access_token),
		tb_access_token_secret => MIME::Base64::encode_base64($s_access_token_secret),
		user_id => $user_id,
		base_hostname => $base_hostname,
		target => $target,
		since_id => $since_id,
	};

	# DB格納
	my $oid = $self->pastes->insert($access_tokens);
	return $self->redirect_to( 'complete' );
} => 'auth_cb';

get '/complete' => sub {
	my $self = shift;
	$self->session( expires => 1 );
	return $self->render(
		template => 'complete',
		type => '登録'
	);
} => 'compete';

get '/logout' => sub {
	my $self = shift;
	$self->session( expires => 1 );
	$self->redirect_to( 'index' );
} => 'logout';

app->sessions->secure(1);
app->secrets(["xxx"]); # セッション管理のために付けておく
app->start;

