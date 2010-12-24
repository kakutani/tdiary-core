# -*- coding: utf-8; -*-

require 'stringio'
require 'tdiary'
require 'tdiary/tdiary_response'

module TDiary
	class Dispatcher
		class << self
			# stolen from Rack::Handler::CGI.send_headers
			def send_headers( status, headers )
				$stdout.print "Status: #{status}\r\n"
				$stdout.print CGI.new.header( headers )
				$stdout.flush
			end

			# stolen from Rack::Handler::CGI.send_body
			def send_body( body )
				body.each { |part|
					$stdout.print part
					$stdout.flush
				}
			end

			# FIXME temporary method during (scratch) refactoring
			def extract_status_for_legacy_tdiary( head )
				status_str = head.delete('status')
				return 200 if !status_str || status_str.empty?
				if m = status_str.match(/(\d+)\s(.+)\Z/)
					m[1].to_i
				else
					200
				end
			end
		end

		class IndexMain
			def self.run( request, cgi )
				new( request, cgi ).run
			end

			attr_reader :request, :cgi, :conf, :tdiary, :params

			def initialize( request, cgi )
				@request = request
				@cgi = cgi
				@conf = TDiary::Config::new( cgi, request )
				@params = request.params
			end

			def run
				begin
					status = nil
					if %r[/\d{4,8}(-\d+)?\.html?$] =~ @cgi.redirect_url and not @cgi.valid?( 'date' )
						@cgi.params['date'] = [@cgi.redirect_url.sub( /.*\/(\d+)(-\d+)?\.html$/, '\1\2' )]
						status = CGI::HTTP_STATUS['OK']
					end

					@tdiary = create_tdiary

					begin
						head = {
							'Content-Type' => 'text/html',
							'Vary' => 'User-Agent'
						}
						head['status'] = status if status
						body = ''
						head['Last-Modified'] = CGI::rfc1123_date( tdiary.last_modified )

						if request.head?
							head['Pragma'] = 'no-cache'
							head['Cache-Control'] = 'no-cache'
							return TDiary::Response.new( '', 200, head )
						else
							if request.mobile_agent?
								body = conf.to_mobile( tdiary.eval_rhtml( 'i.' ) )
								head['charset'] = conf.mobile_encoding
								head['Content-Length'] = body.bytesize.to_s
							else
								require 'digest/md5'
								body = tdiary.eval_rhtml
								head['ETag'] = %Q["#{Digest::MD5.hexdigest( body )}"]
								if ENV['HTTP_IF_NONE_MATCH'] == head['ETag'] and request.get? then
									status = CGI::HTTP_STATUS['NOT_MODIFIED']
									body = ''
								else
									head['charset'] = conf.encoding
									head['Content-Length'] = body.bytesize.to_s
								end
								head['Pragma'] = 'no-cache'
								head['Cache-Control'] = 'no-cache'
								head['X-Frame-Options'] = conf.x_frame_options if conf.x_frame_options
							end
							head['cookie'] = tdiary.cookies if tdiary.cookies.size > 0
							TDiary::Response.new( body, ::TDiary::Dispatcher.extract_status_for_legacy_tdiary( head ), head )
						end
					rescue TDiary::NotFound
						body = %Q[
									<h1>404 Not Found</h1>
									<div>#{' ' * 500}</div>]
						TDiary::Response.new( body, 404, { 'Content-Type' => 'text/html' } )
					end
				rescue TDiary::ForceRedirect
					head = {
						#'Location' => $!.path
						'Content-Type' => 'text/html',
					}
					body = %Q[
								<html>
								<head>
								<meta http-equiv="refresh" content="1;url=#{$!.path}">
								<title>moving...</title>
								</head>
								<body>Wait or <a href="#{$!.path}">Click here!</a></body>
								</html>]
					head['cookie'] = tdiary.cookies if tdiary && tdiary.cookies.size > 0
					# TODO return code should be 302? (current behaviour returns 200)
					TDiary::Response.new( body, 200, head )
				end
			end

			def create_tdiary
				begin
					if params['comment']
						tdiary = TDiary::TDiaryComment::new( cgi, "day.rhtml", conf, request )
					elsif (date = params['date'])
						if /^\d{8}-\d+$/ =~ date
							tdiary = TDiary::TDiaryLatest::new( cgi, "latest.rhtml", conf, request )
						elsif /^\d{8}$/ =~ date
							tdiary = TDiary::TDiaryDay::new( cgi, "day.rhtml", conf, request )
						elsif /^\d{6}$/ =~ date
							tdiary = TDiary::TDiaryMonth::new( cgi, "month.rhtml", conf, request )
						elsif /^\d{4}$/ =~ date
							tdiary = TDiary::TDiaryNYear::new( cgi, "month.rhtml", conf, request )
						end
					elsif params['category']
						tdiary = TDiary::TDiaryCategoryView::new( cgi, "category.rhtml", conf, request )
					elsif params['q']
						tdiary = TDiary::TDiarySearch::new( cgi, "search.rhtml", conf, request )
					else
						tdiary = TDiary::TDiaryLatest::new( cgi, "latest.rhtml", conf, request )
					end
				rescue TDiary::PermissionError
					raise
				rescue TDiary::TDiaryError
				end
				( tdiary ? tdiary : TDiary::TDiaryLatest::new( cgi, "latest.rhtml", conf, request ) )
			end
		end

		class UpdateMain
			def self.run( request, cgi )
				new( request, cgi ).run
			end

			attr_reader :request, :cgi, :conf, :tdiary, :params

			def initialize( request, cgi )
				@request = request
				@cgi = cgi
				@conf = TDiary::Config::new( cgi, request )
				@params = request.params
			end

			def run
				@tdiary = create_tdiary
				begin
					head = {}; body = ''
					if request.mobile_agent?
						body = conf.to_mobile( tdiary.eval_rhtml( 'i.' ) )
						head = {
							'Content-Type' => 'text/html',
							'charset' => conf.mobile_encoding,
							'Content-Length' => body.bytesize.to_s,
							'Vary' => 'User-Agent'
						}
					else
						body = tdiary.eval_rhtml
						head = {
							'Content-Type' => 'text/html',
							'charset' => conf.encoding,
							'Content-Length' => body.bytesize.to_s,
							'Vary' => 'User-Agent'
						}
					end
					body = ( request.head? ? '' : body )
					TDiary::Response.new( body, 200, head )
				rescue TDiary::ForceRedirect
					head = {
						#'Location' => $!.path
						'Content-Type' => 'text/html',
					}
					body = %Q[
								<html>
								<head>
								<meta http-equiv="refresh" content="1;url=#{$!.path}">
								<title>moving...</title>
								</head>
								<body>Wait or <a href="#{$!.path}">Click here!</a></body>
								</html>]
					head['cookie'] = tdiary.cookies if tdiary.cookies.size > 0
					# TODO return code should be 302? (current behaviour returns 200)
					TDiary::Response.new( body, 200, head )
				end
			end

			private
			def create_tdiary
				begin
					if params['append']
						tdiary = TDiary::TDiaryAppend::new( cgi, 'show.rhtml', conf, request )
					elsif params['edit']
						tdiary = TDiary::TDiaryEdit::new( cgi, 'update.rhtml', conf, request )
					elsif params['replace']
						tdiary = TDiary::TDiaryReplace::new( cgi, 'show.rhtml', conf, request )
					elsif params['appendpreview'] or params['replacepreview']
						tdiary = TDiary::TDiaryPreview::new( cgi, 'preview.rhtml', conf, request )
					elsif params['plugin']
						tdiary = TDiary::TDiaryFormPlugin::new( cgi, 'update.rhtml', conf, request )
					elsif params['comment']
						tdiary = TDiary::TDiaryShowComment::new( cgi, 'update.rhtml', conf, request )
					elsif params['saveconf']
						tdiary = TDiary::TDiarySaveConf::new( cgi, 'conf.rhtml', conf, request )
					elsif params['conf']
						tdiary = TDiary::TDiaryConf::new( cgi, 'conf.rhtml', conf, request )
					elsif params['referer']
						tdiary = TDiary::TDiaryConf::new( cgi, 'referer.rhtml', conf, request )
					else
						tdiary = TDiary::TDiaryForm::new( cgi, 'update.rhtml', conf, request )
					end
				rescue TDiary::TDiaryError
					tdiary = TDiary::TDiaryForm::new( cgi, 'update.rhtml', conf, request )
				end
				tdiary
			end
		end

		TARGET = {
			:index => IndexMain,
			:update => UpdateMain
		}

		class << self
			def index
				new( :index )
			end

			def update
				new( :update )
			end
			private :new
		end

		def initialize( target )
			@target = TARGET[target]
		end

		# FIXME rename method name to more suitable one.
		def dispatch_cgi( request, cgi = CGI.new )
			result = @target.run( request, cgi )
			result.headers.reject!{|k,v| k.to_s.downcase == "status" }
			result.to_a
		end
	end
end

# Local Variables:
# mode: ruby
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# End:
