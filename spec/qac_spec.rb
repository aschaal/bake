#!/usr/bin/env ruby

require 'helper'

require 'common/version'

require 'bake/options/options'
require 'common/exit_helper'
require 'fileutils'

module Bake

  VISIBLE_RCF = File.dirname(__FILE__)+"/bin/config/rcf/mcpp-1_5_1-en_US.rcf"
  HIDDEN_RCF  = File.dirname(__FILE__)+"/bin/config/rcf/_mcpp-1_5_1-en_US.rcf"

  VISIBLE_RCF2 = File.dirname(__FILE__)+"/mcpp-1.5.1"
  HIDDEN_RCF2  = File.dirname(__FILE__)+"/_mcpp-1.5.1"


  def self.hideRcf()
    FileUtils.mv(Bake::VISIBLE_RCF, Bake::HIDDEN_RCF) if File.exist?(Bake::VISIBLE_RCF)
  end
  def self.showRcf2()
    FileUtils.mv(Bake::HIDDEN_RCF2, Bake::VISIBLE_RCF2) if File.exist?(Bake::HIDDEN_RCF2)
  end

  def self.startBakeqac(proj, opt)
    cmd = ["ruby", "bin/bakeqac","-m", "spec/testdata/#{proj}"].concat(opt).join(" ")
    puts `#{cmd}`
    exit_code = $?.exitstatus
    Bake::cleanup
    exit_code
  end

  def self.getCct(cVersion = "")
    gccVersion = Bake::Toolchain::getGccVersion

    plStr = nil
    gccPlatform = Bake::Toolchain::getGccPlatform
    if gccPlatform.include?"mingw"
      plStr = "w64-mingw32"
    elsif gccPlatform.include?"cygwin"
      plStr = "pc-cygwin"
    elsif gccPlatform.include?"linux"
      plStr = "generic-linux"
    end

    if plStr.nil? # fallback
      if RUBY_PLATFORM =~ /mingw/
        plStr = "w64-mingw32"
      elsif RUBY_PLATFORM =~ /cygwin/
        plStr = "pc-cygwin"
      else
        plStr = "generic-linux"
      end
    end

    cct = ""
    while (cct == "" or gccVersion[0]>=4)
      cct = "config/cct/GNU_GCC-g++_#{gccVersion[0]}.#{gccVersion[1]}-i686-#{plStr}-C++#{cVersion}.cct"
      break if File.exist?cct
      cct = "config/cct/GNU_GCC-g++_#{gccVersion[0]}.#{gccVersion[1]}-x86_64-#{plStr}-C++#{cVersion}.cct"
      break if File.exist?cct
      if gccVersion[1]>0
        gccVersion[1] -= 1
      else
        gccVersion[0] -= 1
        gccVersion[1] = 20
      end
    end

    return cct
  end

describe "Qac" do

  after(:each) do
    FileUtils.mv(Bake::HIDDEN_RCF, Bake::VISIBLE_RCF) if File.exist?(Bake::HIDDEN_RCF)
    FileUtils.mv(Bake::VISIBLE_RCF2, Bake::HIDDEN_RCF2) if File.exist?(Bake::VISIBLE_RCF2)
    ENV.delete("MCPP_HOME")
  end

  it 'gcc version test' do
    $oldGccVersion = Bake::Toolchain.method(:getGccRawVersionInfo)

    module Bake::Toolchain
      def self.getGccRawVersionInfo
        "g++ (Uhu 5.4.0-etc) 5.4.0 20160101\nbla bla bla Inc."
      end
    end
    expect(Bake::Toolchain::getGccVersion).to be == [5,4,0]
    module Bake::Toolchain
      def self.getGccRawVersionInfo
        "g++.exe (GCC) 4.8.2\nbla bla bla Inc."
      end
    end
    expect(Bake::Toolchain::getGccVersion).to be == [4,8,2]

    module Bake::Toolchain
      def self.getGccRawVersionInfo
        $oldGccVersion.call()
      end
    end
  end

  it 'qac installed' do
    begin
      `qacli --version`
      $qacInstalled = true
    rescue Exception
      if not Bake.ciRunning?
        fail "qac not installed" # fail only once on non qac systems
      end
    end
  end

  it 'integration test' do
    if $qacInstalled

      exit_code = Bake.startBakeqac("qac/main/src", ["test_template", "--qacretry", "60", "--qacdoc"])

      $mystring.gsub!(/\\/,"/")

      expect($mystring.include?("bakeqac: creating database...")).to be == true
      expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
      expect($mystring.include?("bakeqac: printing results...")).to be == true

      expect($mystring.include?("spec/testdata/qac/lib/src/lib.cpp")).to be == true
      expect($mystring.include?("spec/testdata/qac/main/include/A.h")).to be == true
      expect($mystring.include?("spec/testdata/qac/main/src/main.cpp")).to be == true

      results = $mystring.split("bakeqac: printing results")[1]
      
      expect(results.include?("spec/testdata/qac/main/mock/src/mock.cpp")).to be == false
      expect(results.include?("spec/testdata/qac/gtest/src/gtest.cpp")).to be == false

      expect($mystring.include?("doc: ")).to be == true

      expect(exit_code).to be == 0
    end
  end

  it 'version' do
    exit_code = Bake.startBakeqac("qac/main", ["--version"])
    expect($mystring.include?("-- bakeqac")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be == 0
  end

  it 'help1' do
    exit_code = Bake.startBakeqac("qac/main", ["-h"])
    expect($mystring.include?("Usage:")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be == 0
  end

  it 'help2' do
    exit_code = Bake.startBakeqac("qac/main", ["--help"])
    expect($mystring.include?("Usage:")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be == 0
  end

  it 'simple test' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == true
    expect($mystring.include?("Number of messages: 0")).to be == true
    expect(exit_code).to be == 0
  end

  it 'no_home' do
    ENV.delete("QAC_HOME")
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("Error: specify the environment variable QAC_HOME.")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be > 0
  end

  it 'home' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "home"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "admin", "--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bake/spec/bin = HOME")).to be == true
    expect(exit_code).to be == 0
  end

  it 'wrong_step' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "\"wrong|admin\"", "--qacunittest"])
    expect($mystring.include?("Error: incorrect qacstep name.")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be > 0
  end

  it 'steps_all1' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == true
    expect(exit_code).to be == 0
  end

  it 'steps_all2' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "\"admin|view|analyze\"", "--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == true
    expect(exit_code).to be == 0
  end

  it 'steps_failureAdmin' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_failureAdmin"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == false
    expect($mystring.include?("bakeqac: printing results...")).to be == false
    expect(exit_code).to be > 0
  end

  it 'steps_failureAnalyze' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_failureAnalyze"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == false
    expect(exit_code).to be > 0
  end

  it 'steps_failureView' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_failureView"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == true
    # expect(exit_code).to be > 0
    expect(exit_code).to be == 0 # HACK, see bakeqac
  end

  it 'steps_onlyAdmin' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "admin", "--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == false
    expect($mystring.include?("bakeqac: printing results...")).to be == false
    expect(exit_code).to be == 0
  end

  it 'steps_onlyAnalyze' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "analyze", "--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == false
    expect(exit_code).to be == 0
  end

  it 'steps_onlyView' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "view", "--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == false
    expect($mystring.include?("bakeqac: printing results...")).to be == true
    expect(exit_code).to be == 0
  end

  it 'steps_AnalyzeAndView' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    exit_code = Bake.startBakeqac("qac/main", ["--qacstep", "\"analyze|view\"", "--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect($mystring.include?("bakeqac: building and analyzing files...")).to be == true
    expect($mystring.include?("bakeqac: printing results...")).to be == true
    expect(exit_code).to be == 0
  end

  it 'steps_qacdata' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_qacdata"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacnofilter"])
    admin = $mystring.match(/admin:.*spec\/testdata\/qac\/main\/\.qacdata\/run1\*/)
    analyze = $mystring.match(/analyze:.*spec\/testdata\/qac\/main\/\.qacdata\/run1\*/)
    view = $mystring.match(/view:.*spec\/testdata\/qac\/main\/\.qacdata\/run1\*/)
    expect(admin && admin.length > 0).to be == true
    expect(analyze && analyze.length > 0).to be == true
    expect(view && view.length > 0).to be == true
    expect(exit_code).to be == 0
  end

  it 'steps_qacdataUser' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_qacdata"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacdata", "\"testQacData\\bla\"", "--qacnofilter"])
    expect($mystring.include?("admin: *testQacData/bla/run1*")).to be == true
    expect($mystring.include?("analyze: *testQacData/bla/run1*")).to be == true
    expect($mystring.include?("view: *testQacData/bla/run1*")).to be == true
    expect(exit_code).to be == 0
  end

  it 'acf_user' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--acf", "\"#{ENV["QAC_HOME"]}config/acf\\fasel.acf\""])
    expect($mystring.include?("config/acf/fasel.acf - ACF")).to be == true
    expect(exit_code).to be == 0
  end

  it 'acf_default' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin"])
    expect($mystring.include?("config/acf/default.acf - ACF")).to be == true
    expect(exit_code).to be == 0
  end

  it 'rcf_user' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--rcf", "\"#{ENV["QAC_HOME"]}config/rcf\\fasel.rcf\""])
    expect($mystring.include?("config/rcf/fasel.rcf - RCF")).to be == true
    expect(exit_code).to be == 0
  end

  it 'rcf_default' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin"])
    expect($mystring.include?("config/rcf/mcpp-1_5_1-en_US.rcf - RCF")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct_file' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    FileUtils.cp("spec/testdata/qac/_qac.cct", "spec/testdata/qac/qac.cct")
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin"])
    expect($mystring.include?("++.cct - CCT")).to be == true
    ccts = Dir.glob("spec/testdata/qac/main/.qacdata/**/*.cct")
    data = File.read(ccts[0])
    expect(data.include?("Hello")).to be == true
  expect(data.include?("-d _cdecl")).to be == false
    expect(exit_code).to be == 0
    FileUtils.rm_f("spec/testdata/qac/qac.cct")
  end

  it 'cct_file' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--qaccctpatch"])
    expect($mystring.include?("++.cct - CCT")).to be == true
    ccts = Dir.glob("spec/testdata/qac/main/.qacdata/**/*.cct")
    data = File.read(ccts[0])
    expect(data.include?("Hello")).to be == false
    expect(data.include?("-d _cdecl")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct user_1' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--cct", "\"#{ENV["QAC_HOME"]}config/cct\\fasel.cct\""])
    expect($mystring.include?("config/cct/fasel.cct - CCT")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct user_2' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--cct", "\"#{ENV["QAC_HOME"]}config/cct\\fasel.cct\"", "--cct", "\"#{ENV["QAC_HOME"]}config/cct\\more.cct\""])
    expect($mystring.include?("config/cct/fasel.cct - CCT")).to be == true
    expect($mystring.include?("config/cct/more.cct - CCT")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct auto' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin"])
    expect($mystring.include?("#{Bake.getCct} - CCT")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct auto 11' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--c++11"])
      puts Bake.getCct("--c++11")
    expect($mystring.include?("#{Bake.getCct("-c++11")} - CCT")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct auto 14' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--c++14"])
    expect($mystring.include?("#{Bake.getCct("-c++14")} - CCT")).to be == true
    expect(exit_code).to be == 0
  end

  it 'main dir not found' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    exit_code = Bake.startBakeqac("qac/main2", ["--qacunittest"])
    expect($mystring.include?("Error: Directory spec/testdata/qac/main2 does not exist")).to be == true
    expect(exit_code).to be > 0
  end

  it 'main dir not found' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    exit_code = Bake.startBakeqac("qac/main/Project.meta", ["--qacunittest"])
    expect($mystring.include?("Error: spec/testdata/qac/main/Project.meta is not a directory")).to be == true
    expect(exit_code).to be > 0
  end

  it 'oldformat' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "old_format"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "-b", "Dummy", "--qacrawformat"])

    expect($mystring.include?("FORMAT: old")).to be == true
    expect($mystring.include?("Number of messages: 4")).to be == true
    expect(exit_code).to be == 0
  end

  it 'newformat' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "new_format"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])

    expect($mystring.include?("FORMAT: new")).to be == true
    expect($mystring.include?("Number of messages: 5")).to be == true
    expect(exit_code).to be == 0
  end

  it 'filter' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "new_format"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("rspec/lib1")).to be == true
    expect($mystring.include?("rspec/lib2")).to be == true
    expect($mystring.include?("rspec/lib3")).to be == false
    expect($mystring.include?("rspec/lib1/test")).to be == false
    expect($mystring.include?("rspec/lib1/mock")).to be == false
    expect($mystring.include?("rspec/gmook")).to be == false
    expect($mystring.include?("rspec/gtest")).to be == false
    expect($mystring.include?("QAC++ Deep Flow Static Analyser")).to be == false
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("Project path")).to be == false
    expect($mystring.include?("Rebuilding done.")).to be == true
    expect(exit_code).to be == 0
  end

  it 'no msg filter' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "new_format"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacnomsgfilter"])
    expect($mystring.include?("rspec/lib1/")).to be == true
    expect($mystring.include?("rspec/lib2/")).to be == true
    expect($mystring.include?("rspec/lib3/")).to be == false
    expect($mystring.include?("rspec/lib1/test/")).to be == false
    expect($mystring.include?("rspec/lib1/mock/")).to be == false
    expect($mystring.include?("rspec/gmock/")).to be == false
    expect($mystring.include?("rspec/gtest/")).to be == false
    expect($mystring.include?("QAC++ Deep Flow Static Analyser")).to be == true
    expect($mystring.include?("Filtered out 1")).to be == true
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("Project path")).to be == true
    expect($mystring.include?("Rebuilding done.")).to be == true
    expect(exit_code).to be == 0
  end

  it 'no file filter' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "new_format"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacnofilefilter"])
    expect($mystring.include?("rspec/lib1/")).to be == true
    expect($mystring.include?("rspec/lib2/")).to be == true
    expect($mystring.include?("rspec/lib3/")).to be == true
    expect($mystring.include?("rspec/lib1/test/")).to be == true
    expect($mystring.include?("rspec/lib1/mock/")).to be == true
    expect($mystring.include?("rspec/gmock/")).to be == true
    expect($mystring.include?("rspec/gtest/")).to be == true
    expect($mystring.include?("QAC++ Deep Flow Static Analyser")).to be == false
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("Project path")).to be == false
    expect($mystring.include?("Rebuilding done.")).to be == true
    expect(exit_code).to be == 0
  end

  it 'no filter.txt' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "new_format"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacnofilter", "--qacstep view"])
    expect($mystring.include?("rspec/lib1")).to be == true
    expect($mystring.include?("rspec/lib2")).to be == true
    expect($mystring.include?("rspec/lib3")).to be == true
    expect($mystring.include?("rspec/lib1/test")).to be == true
    expect($mystring.include?("rspec/lib1/mock")).to be == true
    expect($mystring.include?("rspec/gmock")).to be == true
    expect($mystring.include?("rspec/gtest")).to be == true
    expect($mystring.include?("QAC++ Deep Flow Static Analyser")).to be == true
    expect($mystring.include?("Filtered out 2")).to be == true
    expect(exit_code).to be == 0
  end

  it 'no license analyze' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_analyze"
    ENV["QAC_RETRY"] = "0"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("License Refused")).to be == true
    expect($mystring.include?("Filtered out 1")).to be == true
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("rspec/lib1/bla")).to be == false
    expect($mystring.include?("rspec/lib2/bla")).to be == false
    expect(exit_code).to be > 0
  end

  it 'no license view' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_view"
    ENV["QAC_RETRY"] = "0"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("License Refused")).to be == true
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == true
    expect($mystring.include?("rspec/lib1/bla")).to be == true
    expect($mystring.include?("rspec/lib2/bla")).to be == true
    expect(exit_code).to be > 0
  end

  it 'no license view c' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_view_c"
    ENV["QAC_RETRY"] = "0"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("License Refused")).to be == false
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("rspec/lib1/bla")).to be == true
    expect($mystring.include?("rspec/lib2/bla")).to be == false
    expect(exit_code).to be == 0
  end

  it 'no license analyze retry' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_analyze"
    ENV["QAC_RETRY"] = Time.now.to_i.to_s
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacretry", "15"]) # after 5s the license is available
    expect($mystring.split("License refused").length).to be > 3
    expect($mystring.split("License refused").length).to be < 20
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("rspec/lib1/bla")).to be == true
    expect($mystring.include?("rspec/lib2/bla")).to be == false
    expect(exit_code).to be == 0
  end

  it 'no license view retry' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_view"
    ENV["QAC_RETRY"] = Time.now.to_i.to_s
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacretry", "10"]) # after 5s the license is available
    expect($mystring.split("License refused").length).to be >= 3
    expect($mystring.split("License refused").length).to be < 10
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("rspec/lib1/bla")).to be == true
    expect($mystring.include?("rspec/lib2/bla")).to be == false
    expect(exit_code).to be == 0
  end

  it 'no license view c retry' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_view_c"
    ENV["QAC_RETRY"] = Time.now.to_i.to_s
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacretry", "10"]) # after 5s the license is available
    expect($mystring.split("License refused").length).to be == 1
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("rspec/lib1/bla")).to be == true
    expect($mystring.include?("rspec/lib2/bla")).to be == false
    expect(exit_code).to be == 0
  end

  it 'no license analyze retry timeout' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_analyze"
    ENV["QAC_RETRY"] = Time.now.to_i.to_s
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacretry", "3"]) # after 5s the license is available
    expect($mystring.split("License refused").length).to be > 3
    expect($mystring.include?("Retry timeout")).to be == true
    expect($mystring.include?("Filtered out 1")).to be == true
    expect($mystring.include?("Filtered out 2")).to be == false
    expect($mystring.include?("rspec/lib1/bla")).to be == false
    expect($mystring.include?("rspec/lib2/bla")).to be == false
    expect(exit_code).to be > 0
  end

  it 'no license view retry timeout' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "no_license_view"
    ENV["QAC_RETRY"] = Time.now.to_i.to_s
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacretry", "3"]) # after 5s the license is available
    expect($mystring.split("License refused").length).to be > 3
    expect($mystring.include?("Retry timeout")).to be == true
    expect($mystring.include?("Filtered out 1")).to be == false
    expect($mystring.include?("Filtered out 2")).to be == true
    expect($mystring.include?("rspec/lib1/bla")).to be == true
    expect($mystring.include?("rspec/lib2/bla")).to be == true
    expect(exit_code).to be > 0
  end

  it 'without default' do

    if File.exist?("spec/testdata/qac/config/ProjectOrg.meta")
      FileUtils.mv("spec/testdata/qac/config/Project.meta", "spec/testdata/qac/config/Project2.meta")
      FileUtils.mv("spec/testdata/qac/config/ProjectOrg.meta", "spec/testdata/qac/config/Project.meta")
    end

    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 3
    expect($mystring.split("CHANGED").length).to be == 1
    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 5
    expect($mystring.split("CHANGED").length).to be == 1
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 5
    expect($mystring.split("CHANGED").length).to be == 3
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 5
    expect($mystring.split("CHANGED").length).to be == 5

    FileUtils.mv("spec/testdata/qac/config/Project.meta", "spec/testdata/qac/config/ProjectOrg.meta")
    FileUtils.mv("spec/testdata/qac/config/Project2.meta", "spec/testdata/qac/config/Project.meta")
    sleep 2
    FileUtils.touch("spec/testdata/qac/config/Project.meta")

    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 7
    expect($mystring.split("CHANGED").length).to be == 5
    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 9
    expect($mystring.split("CHANGED").length).to be == 5
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 11
    expect($mystring.split("CHANGED").length).to be == 5
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 13
    expect($mystring.split("CHANGED").length).to be == 5

    FileUtils.mv("spec/testdata/qac/config/Project.meta", "spec/testdata/qac/config/Project2.meta")
    FileUtils.mv("spec/testdata/qac/config/ProjectOrg.meta", "spec/testdata/qac/config/Project.meta")
    sleep 2
    FileUtils.touch("spec/testdata/qac/config/Project.meta")

    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 15
    expect($mystring.split("CHANGED").length).to be == 5
    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 17
    expect($mystring.split("CHANGED").length).to be == 5
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 17
    expect($mystring.split("CHANGED").length).to be == 7
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 17
    expect($mystring.split("CHANGED").length).to be == 9

  end

  it 'with default' do
    exit_code = Bake.startBake("qac/default", ["test"])
    expect($mystring.split("NORMAL").length).to be == 3
    expect($mystring.split("CHANGED").length).to be == 1
    exit_code = Bake.startBake("qac/config", ["test"])
    expect($mystring.split("NORMAL").length).to be == 5
    expect($mystring.split("CHANGED").length).to be == 1
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 5
    expect($mystring.split("CHANGED").length).to be == 3
    exit_code = Bake.startBake("qac/config", ["test", "--qac"])
    expect($mystring.split("NORMAL").length).to be == 5
    expect($mystring.split("CHANGED").length).to be == 5
  end

  it 'mdr_test_okay' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "mdr_test_okay"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin,analyze,mdr"])

    expect($mystring.include?("lib2")).to be == false
    expect($mystring.include?("lib1/src/File1.cpp")).to be == true
    expect($mystring.include?("Func1:11: cyclomatic complexity = 13")).to be == true
    expect($mystring.include?("Func2:22: cyclomatic complexity = 2")).to be == true
    expect($mystring.include?("Maximum cyclomatic complexity: 13")).to be == true
    expect($mystring.include?("umber of functions with cyclomatic complexity more than accepted: 1")).to be == true
    expect(exit_code).to be == 0
  end

  it 'mdr_test_okay no filter' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "mdr_test_okay"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "\"admin|analyze|mdr\"", "--qacnofilter"])

    expect($mystring.include?("lib2")).to be == true
    expect($mystring.include?("lib1/src/File1.cpp")).to be == true
    expect($mystring.include?("Func1:11: cyclomatic complexity = 13")).to be == true
    expect($mystring.include?("Func2:22: cyclomatic complexity = 2")).to be == true
    expect($mystring.include?("Maximum cyclomatic complexity: 14")).to be == true
    expect($mystring.include?("umber of functions with cyclomatic complexity more than accepted: 2")).to be == true
    expect(exit_code).to be == 0
  end

  it 'mdr_test_suppress' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "mdr_test_suppress"
    exit_code = Bake.startBakeqac("stcyc/main", ["--qacunittest", "--qacstep", "mdr"])
    expect($mystring.include?("FuncA:1: cyclomatic complexity = 12 (warning: accepted = 10)")).to be == true
    expect($mystring.include?("FuncB:2: cyclomatic complexity = 12 (info: accepted = 12)")).to be == true
    expect($mystring.include?("FuncC1:2: cyclomatic complexity = 12 (warning: accepted = 10)")).to be == true
    expect($mystring.include?("FuncC2:22: cyclomatic complexity = 12 (info: accepted = 12)")).to be == true
    expect($mystring.include?("FuncD1:4: cyclomatic complexity = 12 (info: accepted = 12)")).to be == true
    expect($mystring.include?("FuncD2:23: cyclomatic complexity = 12 (warning: accepted = 10)")).to be == true
    expect($mystring.include?("FuncE1:3: cyclomatic complexity = 12 (info: accepted = 17)")).to be == true
    expect($mystring.include?("FuncE2:22: cyclomatic complexity = 1")).to be == true
    expect($mystring.include?("FuncE2:27: cyclomatic complexity = 16 (warning: accepted = 12)")).to be == true
    expect($mystring.include?("FuncF1:3: cyclomatic complexity = 12 (warning: accepted = 10)")).to be == true
    expect($mystring.include?("FuncF2:23: cyclomatic complexity = 12 (warning: accepted = 10)")).to be == true
    expect($mystring.include?("**** Maximum cyclomatic complexity: 16 ****")).to be == true
    expect($mystring.include?("**** Number of functions with cyclomatic complexity more than accepted: 6 ****")).to be == true
    expect(exit_code).to be == 0
  end

  it 'mcpp home not found' do
    Bake.hideRcf()

    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("Error: cannot find MCPP home folder. Specify MCPP_HOME.")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be > 0
  end

  it 'mcpp home invalid' do
    Bake.hideRcf()

    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    ENV["MCPP_HOME"] = "wrooong"

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("Error: MCPP_HOME points to invalid directory:")).to be == true
    expect($mystring.include?("bakeqac: creating database...")).to be == false
    expect(exit_code).to be > 0
  end

  it 'mcpp home valid' do
    Bake.hideRcf()

    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"
    ENV["MCPP_HOME"] = Bake::HIDDEN_RCF2

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect(exit_code).to be == 0
  end


  it 'mcpp included' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect(exit_code).to be == 0
  end

  it 'mcpp beside' do
    Bake.hideRcf()
    Bake.showRcf2()

    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "steps_ok"

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest"])
    expect($mystring.include?("bakeqac: creating database...")).to be == true
    expect(exit_code).to be == 0
  end

  it 'mcpp prio included > beside' do
    Bake.showRcf2()

    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin"])
    expect($mystring.include?("spec/bin/config/rcf/mcpp-1_5_1-en_US.rcf")).to be == true
    expect(exit_code).to be == 0
  end

  it 'mcpp prio env > included' do
    ENV["MCPP_HOME"] = Bake::HIDDEN_RCF2

    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"

    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin"])
    expect($mystring.include?("/spec/_mcpp-1.5.1/config/rcf/mcpp-1_5_1-en_US.rcf")).to be == true
    expect(exit_code).to be == 0
  end

  it 'cct not found' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--cct", "wroong"])
    expect($mystring.include?("Error: cct file not found: wroong")).to be == true
    expect(exit_code).to be > 0
  end

  it 'acf not found' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--acf", "wroong"])
    expect($mystring.include?("Error: acf file not found: wroong")).to be == true
    expect(exit_code).to be > 0
  end

  it 'rcf not found' do
    ENV["QAC_HOME"] = File.dirname(__FILE__)+"/bin\\"
    ENV["QAC_UT"] = "config_files"
    exit_code = Bake.startBakeqac("qac/main", ["--qacunittest", "--qacstep", "admin", "--rcf", "wroong"])
    expect($mystring.include?("Error: rcf file not found: wroong")).to be == true
    expect(exit_code).to be > 0
  end

end

end
