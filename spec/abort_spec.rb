#!/usr/bin/env ruby

require 'socket'
require 'fileutils'
require 'helper'

require 'coveralls'
Coveralls.wear_merged!

require 'common/version'

require 'bake/options/options'
require 'common/exit_helper'

module Bake

describe "autodir" do
  
  it 'without no_autodir' do
    Bake.startBake("abort/main", ["test", "--rebuild"])
    expect($mystring.include?("hallo")).to be == false
  end

end

end
