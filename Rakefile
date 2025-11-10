# frozen_string_literal: true

# Ruby Whiskey - Rakefile for testing and building all gems

require 'rake'

desc 'Run all tests for all gems'
task :test do
  puts 'Running tests for all Ruby Whiskey gems...'

  gems = %w[whiskey-core whiskey-orm whiskey-vintages whiskey-web whiskey-cli ruby_whiskey]

  gems.each do |gem|
    gem_path = if gem == 'ruby_whiskey'
                 "./#{gem}"
               else
                 "./gems/#{gem}"
               end

    if File.exist?("#{gem_path}/spec")
      puts "Testing #{gem}..."
      system("cd #{gem_path} && rspec") or abort("Tests failed for #{gem}")
    end
  end

  puts 'All tests passed!'
end

desc 'Build all gems'
task :build do
  puts 'Building all Ruby Whiskey gems...'
  # Implementation for building all gems
end

desc 'Clean build artifacts'
task :clean do
  puts 'Cleaning build artifacts...'
  # Implementation for cleaning
end

task default: :test
