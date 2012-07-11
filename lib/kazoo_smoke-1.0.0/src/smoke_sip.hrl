-ifndef(SMOKE_SIP_HRL).

-type sip_version() :: 'SIP/2.0'.
-define(SIP_VERSION_2_0, 'SIP/2.0').

-record(sip_via, {
          version = ?SIP_VERSION_2_0 :: sip_version()
          ,transport = 'udp' :: sip_transport()
          ,host :: ne_binary()
          ,port :: inet:port_number()
          ,params :: wh_proplist()
         }).

-record(sip_uri, {
          display_name :: ne_binary()
         ,scheme = 'sip' :: 'sip' | 'sips'
         ,user :: ne_binary()
         ,password :: binary()
         ,host = <<"nohost">> :: ne_binary()
         ,port :: integer()
         ,params :: wh_proplist()
         ,headers = [] :: wh_proplist()
         }).

-record(sip_req, {
          %% Transport
          socket :: inet:socket()
         ,transport :: module()

         ,sender_ip :: inet:ip_address()
         ,sender_port :: inet:port_number()

          %% Makes up the first line
         ,method = 'INVITE' :: wh_sip:method()
         ,request_uri :: sip_uri() % Request-URI
         ,version = wh_sip:version() :: wh_sip:version()

          %% Request
         ,headers = [] :: wh_sip:headers()
         ,p_headers = [] :: [any()] % processed headers
         ,onrequest :: 'undefined' | onrequest()

          %% Body
         ,body = <<>> :: binary()
         ,buffer = <<>> :: binary()

          %% Response
         ,onresponse :: 'undefined' | onresponse()
         }).

-type onrequest() :: fun().
-type onresponse() :: fun().

-opaque sip_via() :: #sip_via{}.
-opaque sip_req() :: #sip_req{}.
-opaque sip_uri() :: #sip_uri{}.

-type sip_method() ::
        'INVITE'    | %[RFC3261]
        'ACK'       | %[RFC3261]
        'BYE'       | %[RFC3261]
        'CANCEL'    | %[RFC3261]
        'REGISTER'  | %[RFC3261]
        'OPTIONS'   | %[RFC3261]
        'SUBSCRIBE' | %[RFC3265]
        'NOTIFY'    | %[RFC3265]
        'UPDATE'    | %[RFC3311]
        'MESSAGE'   | %[RFC3428]
        'REFER'     | %[RFC3515]
        'INFO'.       %[RFC2976]
-define(METHODS_SUPPORTED, ['INVITE','ACK','BYE','CANCEL','REGISTER','OPTIONS'
                            ,'SUBSCRIBE','NOTIFY','UPDATE','MESSAGE','REFER'
                            ,'INFO'
                           ]).

-type sip_transport() :: 'udp' | 'tcp' | 'tls' | 'sctp'.
-define(TRANSPORTS_SUPPORTED, ['udp', 'tcp', 'tls', 'sctp']).

-type sip_header() :: 'Via' | 'To' | 'From' | 'CSeq' | 'Call-ID' | % these go in all responses
                      'Max-Forwards' | 'Contact' | 'Content-Type' |
                      'Content-Length' |
                      %% Optional Headers
                      'Accept' | 'Accept-Encoding' | 'Accept-Language' |
                      'Alert-Info' | 'Allow' | 'Authentication-Info' |
                      'Authorization' | 'Call-Info' | 'Content-Disposition' |
                      'Content-Encoding' | 'Content-Language' | 'Date' |
                      'Error-Info' | 'Expires' | 'In-Reply-To' | 'Min-Expires' |
                      'MIME-Version' | 'Organization' | 'Priority' |
                      'Proxy-Authenticate' | 'Proxy-Authorization' | 'Proxy-Require' |
                      'Record-Route' | 'Reply-To' | 'Require' | 'Retry-After' |
                      'Route' | 'Server' | 'Subject' | 'Supported' | 'Timestamp' |
                      'Unsupported' | 'User-Agent' | 'Warning' | 'WWW-Authenticate'.
-define(HEADERS_SUPPORTED, ['Via', 'To', 'From', 'CSeq', 'Call-ID', % these go in all responses
                            'Max-Forwards', 'Contact', 'Content-Type',
                            'Content-Length',
                            %% Optional Headers
                            'Accept', 'Accept-Encoding', 'Accept-Language',
                            'Alert-Info', 'Allow', 'Authentication-Info',
                            'Authorization', 'Call-Info', 'Content-Disposition',
                            'Content-Encoding', 'Content-Language', 'Date',
                            'Error-Info', 'Expires', 'In-Reply-To', 'Min-Expires',
                            'MIME-Version', 'Organization', 'Priority',
                            'Proxy-Authenticate', 'Proxy-Authorization', 'Proxy-Require',
                            'Record-Route', 'Reply-To', 'Require', 'Retry-After',
                            'Route', 'Server', 'Subject', 'Supported', 'Timestamp',
                            'Unsupported', 'User-Agent', 'Warning', 'WWW-Authenticate'
                           ]).

-type sip_headers() :: [{sip_header(), iolist()}].

-type sip_status() :: non_neg_integer() | binary().

-type sip_response_code() :: 100 | 180..183 | 199 |
                             200 | 202 | 204 |
                             300..305 | 380 |
                             400..410 | 412..417 | 420..424 | 428 | 429 | 433 |
                             436..438 | 480..489 | 491 | 493 | 494 |
                             500..505 | 513 | 580 |
                             600 | 603 | 604 | 606.

-define(SMOKE_SIP_HRL, true).
-endif.