require File.dirname(__FILE__) + "/../spec_helper"
require File.dirname(__FILE__) + '/../../tdiary/tdiary_application'

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
	fixture_conf = File.expand_path('../fixtures/just_installed.conf', __FILE__)
	rack_conf = File.expand_path('../fixtures/tdiary.conf.rack', __FILE__)
	work_data_dir = File.expand_path('../../tmp/data', __FILE__)
	work_conf = File.expand_path('../../tdiary.conf', __FILE__)

	config.before(:all) do
		FileUtils.cp_r rack_conf, work_conf, :verbose => false
	end

	config.before(:each) do
		FileUtils.mkdir work_data_dir unless FileTest.exist? work_data_dir
		FileUtils.cp_r fixture_conf, File.join(work_data_dir, "tdiary.conf"), :verbose => false unless fixture_conf.empty?
	end

	config.after(:each) do
		FileUtils.rm_r work_data_dir if FileTest.exist? work_data_dir
	end

	config.after(:all) do
		FileUtils.rm_r work_conf
	end
end

Capybara.app = Rack::Builder.new do
	map '/' do
		run TDiary::Application.new(:index)
	end

	map '/index.rb' do
		run TDiary::Application.new(:index)
	end

	map '/update.rb' do
		run TDiary::Application.new(:update)
	end
end

Capybara.save_and_open_page_path = File.dirname(__FILE__) + '/../../tmp'

# Local Variables:
# mode: ruby
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# End:
# vim: ts=3
