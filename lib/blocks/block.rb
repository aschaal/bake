require_relative '../bake/libElement'
require_relative '../bake/model/metamodel'
require_relative '../common/abortException'
require_relative "../multithread/job"
gem "thwait", "0.1.0"
require "thwait"

module Bake

  BUILD_PASSED = 0
  BUILD_FAILED = 1
  BUILD_ABORTED = 2

  module Blocks

    CC2J = []
    ALL_BLOCKS = {}
    ALL_COMPILE_BLOCKS = {}

    class Block

      @@block_counter = 0
      @@delayed_result = true
      @@threads = []

      attr_reader :lib_elements, :projectDir, :library, :executable, :config, :projectName, :configName, :prebuild, :output_dir, :tcs
      attr_accessor :visited, :inDeps, :result, :bes, :besDirect

      def startupSteps
        @startupSteps ||= []
      end

      def preSteps
        @preSteps ||= []
      end

      def mainSteps
        @mainSteps ||= []
      end

      def postSteps
        @postSteps ||= []
      end

      def exitSteps
        @exitSteps ||= []
      end

      def cleanSteps
        @cleanSteps ||= []
      end

      def dependencies
        @dependencies ||= []
      end
      
      def childs
        @childs ||= []
      end

      def parents
        @parents ||= []
      end

      def set_library(library)
        @library = library
      end

      def set_executable(executable)
        @executable = executable
      end

      def qname()
        @projectName + "," + @configName
      end

      def initialize(config, referencedConfigs, prebuild, tcs)
        @inDeps = false
        @prebuild = prebuild
        @visited = false
        @library = nil
        @executable = nil
        @config = config
        @referencedConfigs = referencedConfigs
        @projectName = config.parent.name
        @configName = config.name
        @projectDir = config.get_project_dir
        @result = true
        @tcs = tcs
        @bes = []
        @besDirect = []
        @lib_elements = []

        calcOutputDir
      end

      def getCompileBlocks()
        mainSteps.select { |m| Compile === m }
      end

      def convPath(dir, elem=nil, warnIfLocal=false)
        if dir.respond_to?("name")
          d = dir.name
          elem = dir
        else
          d = dir
        end

        return d if Bake.options.no_autodir

        inc = d.split("/")
        if (inc[0] == "..") # very simple check, but should be okay for 99.9 % of the cases
          if elem and Bake.options.verbose >= 2
            SyncOut.mutex.synchronize do
              Bake.formatter.printInfo("path starts with \"..\"", elem)
            end
          end
        end

        res = []

        return d if (inc[0] == "." || inc[0] == "..") # prio 0: force local

        if (inc[0] == @projectName) # prio 1: the real path magic
          resPathMagic = inc[1..-1].join("/") # within self
          resPathMagic = "." if resPathMagic == ""
          res << resPathMagic
          if warnIfLocal
            if resPathMagic == "."
              Bake.formatter.printInfo("\"#{d}\" uses path magic in IncludeDir, please use \".\" instead", elem)
            else
              Bake.formatter.printInfo("\"#{d}\" uses path magic in IncludeDir, please omit \"#{inc[0]}/\" or use \"./#{resPathMagic}\"", elem) if warnIfLocal
            end
          end
        elsif @referencedConfigs.include?(inc[0])
          dirOther = @referencedConfigs[inc[0]].first.parent.get_project_dir
          resPathMagic = File.rel_from_to_project(@projectDir, dirOther, false)
          postfix = inc[1..-1].join("/")
          resPathMagic = resPathMagic + "/" + postfix if postfix != ""
          resPathMagic = "." if resPathMagic == ""
          res << resPathMagic
          Bake.formatter.printInfo("\"#{d}\" uses path magic in IncludeDir, please use a Dependency to \"#{inc[0]}\" instead", elem) if warnIfLocal
        end

        if File.exist?(@projectDir + "/" + d) # prio 2: local, e.g. "include"
          res << d
        end

        # prio 3: check if dir exists without Project.meta entry
        Bake.options.roots.each do |r|
          absIncDir = r.dir+"/"+d
          if File.exist?(absIncDir)
            res << File.rel_from_to_project(@projectDir,absIncDir,false)
            Bake.formatter.printInfo("\"#{d}\" uses path magic in IncludeDir, please create a Project.meta in \"#{absIncDir}\" or upwards and use a Dependency instead", elem) if warnIfLocal && res.length == 1
          end
        end

        return d if res.empty? # prio 4: fallback, no path found

        res = res.map{ |r| Pathname.new(r).cleanpath.to_s }.uniq

        if warnIfLocal && res.length > 1
          if elem and Bake.options.verbose >= 2
            SyncOut.mutex.synchronize do
              Bake.formatter.printInfo("#{d} matches several paths:", elem)
              puts "  #{res[0]} (chosen)"
              res[1..-1].each { |r| puts "  #{r}" }
            end
          end
        end

        res[0]
      end

      def self.inc_block_counter()
        @@block_counter += 1
      end

      def self.block_counter
        @@block_counter
      end

      def self.reset_block_counter
        @@block_counter = 1
      end

      def self.set_delayed_result
        @@delayed_result = false
      end

      def self.reset_delayed_result
        @@delayed_result = true
      end

      def self.delayed_result
        @@delayed_result
      end

      def self.threads
        @@threads
      end

      def self.waitForAllThreads
        if @@threads.length > 0
          STDOUT.puts "DEBUG_THREADS: Wait for all threads." if Bake.options.debug_threads
          @@threads.each{|t| while not t.join(2) do end}
          @@threads = []
          STDOUT.puts "DEBUG_THREADS: All threads finished." if Bake.options.debug_threads
        end
      end

      def calcIsBuildBlock
        @startupSteps ||= []

        return true if Metamodel::ExecutableConfig === @config
        if Metamodel::CustomConfig === @config
          return true if @config.step
        else
          return true if @config.files.length > 0
        end
        if ((@config.startupSteps && @config.startupSteps.step.length > 0) ||
          (@config.preSteps && @config.preSteps.step.length > 0) ||
          (@config.postSteps && @config.postSteps.step.length > 0) ||
          (@config.exitSteps && @config.exitSteps.step.length > 0) ||
          (@config.cleanSteps && @config.cleanSteps.step.length > 0) ||
          (@config.preSteps && @config.preSteps.step.length > 0))
            return true
        end
        return false
      end

      def isBuildBlock?
        return true if Bake.options.conversion_info
        @isBuildBlock ||= calcIsBuildBlock
      end

      def self.set_num_projects(blocks)
        if Bake.options.verbose >= 2
          @@num_projects = blocks.length
        else
          counter = 0
          blocks.each do |b|
            counter += 1 if b.isBuildBlock?
          end
          @@num_projects = counter
        end
      end

      def executeStep(step, method)
        begin
          @result = step.send(method) && @result
        rescue Bake::SystemCommandFailed => scf
          @result = false
          ProcessHelper.killProcess(true)
        rescue SystemExit => exSys
          @result = false
          ProcessHelper.killProcess(true)
        rescue Exception => ex1
          @result = false
          if not Bake::IDEInterface.instance.get_abort
            SyncOut.mutex.synchronize do
              Bake.formatter.printError("Error: #{ex1.message}")
              puts ex1.backtrace if Bake.options.debug
            end
          end
        end

        if Bake::IDEInterface.instance.get_abort
          raise AbortException.new
        end

        # needed for ctrl-c in Cygwin console
        #####################################
        # additionally, the user has to enable raw mode of Cygwin console: "stty raw".
        # raw mode changes the signals into raw characters.
        # original problem: Cygwin is compiled with broken control handler config,
        # which might not be changed due to backward compatibility.
        # the control handler works only with programs compiled under Cygwin, which is
        # not true for Windows RubyInstaller packages.
        ctrl_c_found = false
        begin
          @@mutexStdinSelect.synchronize do
            while IO.select([$stdin],nil,nil,0) do
              nextChar = $stdin.sysread(1)
              if nextChar == "\x03"
                ctrl_c_found = true
              end
            end
          end
        rescue Exception => e
        end
        raise AbortException.new if ctrl_c_found
        return @result
      end

      def callDeps(method)
        return true if Bake.options.project
        depResult = true
        bes.each do |dep|
          next if Metamodel::IncludeDir === dep
          depResult = (ALL_BLOCKS[dep.name+","+dep.config].send(method) and depResult)
          break if (!depResult) && Bake.options.stopOnFirstError
        end
        return depResult
      end

      def self.waitForFreeThread
        if @@threads.length == Bake.options.threads
          begin
            STDOUT.puts "DEBUG_THREADS: Wait for free thread." if Bake.options.debug_threads
            endedThread = ThreadsWait.new(*@@threads).next_wait
            STDOUT.puts "DEBUG_THREADS: Thread free: #{endedThread.object_id}" if Bake.options.debug_threads
            @@threads.delete(endedThread)
          rescue ErrNoWaitingThread
          end
        end
      end

      def execute_in_thread(steps)
        @@mutex.synchronize do
          Block::waitForFreeThread()
          return if blockAbort?(true)

          tmpstdout = Thread.current[:tmpStdout].nil? ? nil : Thread.current[:tmpStdout].dup
          @@threads << Thread.new(Thread.current[:stdout], tmpstdout, steps) { |outStr, tmpStdout, steps|
            STDOUT.puts "DEBUG_THREADS: Started: #{Thread.current.object_id} (#{@projectName}, #{@config.name})" if Bake.options.debug_threads
            Thread.current[:stdout] = outStr
            Thread.current[:tmpStdout] = tmpStdout
            Thread.current[:steps] = steps
            exceptionOccured = false
            begin
              yield
              exceptionOccured = true
            rescue Bake::SystemCommandFailed => scf # normal compilation error
            rescue SystemExit => exSys
            rescue AbortException => exSys
              Bake::IDEInterface.instance.set_abort(true)
            rescue Exception => ex1
              if !Bake::IDEInterface.instance.get_abort
                SyncOut.mutex.synchronize do
                  Bake.formatter.printError("Error: #{ex1.message}")
                  puts ex1.backtrace if Bake.options.debug
                end

              end
            end
            if !exceptionOccured
              @result = false
              @@delayed_result = false
            end
            STDOUT.puts "DEBUG_THREADS: Stopped: #{Thread.current.object_id} (#{@projectName}, #{@config.name})" if Bake.options.debug_threads
          }

          Block::waitForFreeThread()
          return if blockAbort?(true)
        end
        raise AbortException.new if Bake::IDEInterface.instance.get_abort
      end

      def blockAbort?(res)
        ((not res) || !@@delayed_result) and Bake.options.stopOnFirstError or Bake::IDEInterface.instance.get_abort
      end

      def independent?(method, step)
        method == :execute && (Library === step || Compile === step ||
          (CommandLine === step && step.config.independent) ||
          (Makefile === step && step.config.independent))
      end

      def callSteps(method)
        @config.writeEnvVars()
        Thread.current[:lastCommand] = nil
        @allSteps = (preSteps + mainSteps + postSteps)
        # check if we have to delay the output (if the last step of this block is not in a thread)
        @outputStep = nil
        @allSteps.each { |step| @outputStep = independent?(method, step) ? step : nil }
        while !@allSteps.empty?
          parallel = []
          while @allSteps.first && independent?(method, @allSteps.first)
            parallel << @allSteps.shift
          end
          if parallel.length > 0
            execute_in_thread(parallel) {
              lastStep = Thread.current[:steps].last
               begin
                 Thread.current[:steps].each do |step|
                   Multithread::Jobs.incThread() if !Compile === step
                   begin
                     @result = executeStep(step, :execute) if @result
                   ensure
                     Multithread::Jobs.decThread() if !Compile === step
                   end
                   @@delayed_result &&= @result
                   break if blockAbort?(@result)
                 end
               ensure
                 SyncOut.stopStream() if lastStep == @outputStep if Bake.options.syncedOutput
               end
             }
          else
            step = @allSteps.shift
            Blocks::Block::waitForAllThreads()
            @result = executeStep(step, method) if @result
            @outputStep = nil if !@result && blockAbort?(@result)
          end
          return @result if blockAbort?(@result)
        end

        return @result
      end

      def execute
        if (@inDeps)
          if Bake.options.verbose >= 3
            SyncOut.mutex.synchronize do
              Bake.formatter.printWarning("While calculating next config, a circular dependency was found including project #{@projectName} with config #{@configName}", @config)
            end
          end
          return true
        end

        SyncOut.mutex.synchronize do
          if @visited
            while !defined?(@allSteps) || !@allSteps.empty?
              sleep(0.1)
            end
            return true # maybe to improve later (return false if step has a failed non-independent step)
          end
          @visited = true
        end

        @inDeps = true
        begin
          depResult = callDeps(:execute)
        rescue Exception => e
          @allSteps = []
          raise
        end

        @inDeps = false
        if blockAbort?(depResult)
          @allSteps = []
          return @result && depResult 
        end

        Bake::IDEInterface.instance.set_build_info(@projectName, @configName)
        begin
          SyncOut.mutex.synchronize do
            @outputStep = nil
            SyncOut.startStream() if Bake.options.syncedOutput
            if !Bake.options.skipBuildingLine && (Bake.options.verbose >= 2 || (isBuildBlock? && Bake.options.verbose >= 1))
              typeStr = "Building"
              if @prebuild
                typeStr = "Using"
              elsif not isBuildBlock?
                typeStr = "Applying"
              end

              bcStr = ">>CONF_NUM<<"
              if !Bake.options.syncedOutput
                bcStr = Block.block_counter
                Block.inc_block_counter()
              end

              Bake.formatter.printAdditionalInfo "**** #{typeStr} #{bcStr} of #{@@num_projects}: #{@projectName} (#{@configName}) ****"
            end
            puts "Project path: #{@projectDir}" if Bake.options.projectPaths
          end

          @result = callSteps(:execute)
        ensure
          if Bake.options.syncedOutput
            if !@outputStep
              SyncOut.stopStream()
            else
              SyncOut.discardStreams()
            end
          end
          @allSteps = []
        end
        
        return (depResult && @result)
      end

      def clean
        return true if (@visited)
        @visited = true

        depResult = callDeps(:clean)
        return false if not depResult and Bake.options.stopOnFirstError

        if Bake.options.verbose >= 2
          typeStr = "Cleaning"
          if @prebuild
            typeStr = "Checking"
          elsif not isBuildBlock?
            typeStr = "Skipping"
          end
          Bake.formatter.printAdditionalInfo "**** #{typeStr} #{Block.block_counter} of #{@@num_projects}: #{@projectName} (#{@configName}) ****"
        end

        if Bake.options.verbose >= 2 || (isBuildBlock? && Bake.options.verbose >= 1)
          Block.inc_block_counter()
        end

        @result = callSteps(:clean)

        if Bake.options.clobber
          Dir.chdir(@projectDir) do
            if File.exist?".bake"
              puts "Deleting folder .bake" if Bake.options.verbose >= 2
              if !Bake.options.dry
                FileUtils.rm_rf(".bake")
              end
            end
          end
        end

        cleanSteps.each do |step|
          @result = executeStep(step, :cleanStep) if @result
          return false if not @result and Bake.options.stopOnFirstError
        end

        return (depResult && @result)
      end

      def self.init_threads()
        @@threads = []
        @@result = true
        @@mutex = Mutex.new
        @@mutexStdinSelect = Mutex.new
        Bake::Multithread::Jobs.init_semaphore()
      end

      def startup
        return true if (@visited)
        @visited = true

        depResult = callDeps(:startup)

        if Bake.options.verbose >= 1 and not startupSteps.empty?
          Bake.formatter.printAdditionalInfo "**** Starting up #{@projectName} (#{@configName}) ****"
        end

        startupSteps.each do |step|
          @result = executeStep(step, :startupStep) && @result
        end

        return (depResult && @result)
      end

      def exits
        return true if (@visited)
        @visited = true

        depResult = callDeps(:exits)

        if Bake.options.verbose >= 1 and not exitSteps.empty?
          Bake.formatter.printAdditionalInfo "**** Exiting #{@projectName} (#{@configName}) ****"
        end

        exitSteps.each do |step|
          @result = executeStep(step, :exitStep) && @result
        end

        return (depResult && @result)
      end

      def getSubBlocks(b, method)
        b.send(method).each do |child_b|
          if not @otherBlocks.include?child_b and not child_b == self
            @otherBlocks << child_b
            getSubBlocks(child_b, method)
          end
        end
      end

      def getBlocks(method)
        @otherBlocks = []
        getSubBlocks(self, method)
        return @otherBlocks
      end

      def isMainProject?
        @projectName == Bake.options.main_project_name and @config.name == Bake.options.build_config
      end

      def calcOutputDir
        if @tcs[:OUTPUT_DIR] != nil
          p = convPath(@tcs[:OUTPUT_DIR])
          p = p[2..-1] if p.start_with?("./")
          @output_dir = p
        else
          qacPart = Bake.options.qac ? (".qac" + Bake.options.buildDirDelimiter) : ""
          if isMainProject?
            @output_dir = "build" + Bake.options.buildDirDelimiter + qacPart + Bake.options.build_config
          else
            @output_dir = "build" + Bake.options.buildDirDelimiter + qacPart + @config.name + "_" + Bake.options.main_project_name + "_" + Bake.options.build_config
          end
        end
        if @tcs[:OUTPUT_DIR_POSTFIX] != nil
          @output_dir = @output_dir + @tcs[:OUTPUT_DIR_POSTFIX] 
        end
        if Bake.options.abs_path_in
          @output_dir = File.expand_path(@output_dir, @projectDir)
        end
      end

    end



  end


end