require_relative 'blockBase'

module Bake

  module Blocks

    class Executable < BlockBase

      attr_reader :compileBlock

      def initialize(block, config, referencedConfigs, compileBlock)
        super(block, config, referencedConfigs)
        @compileBlock = compileBlock

        block.set_executable(self)

        calcArtifactName
        calcMapFile
        calcLinkerScript

      end

      def calcLinkerScript
        if Metamodel::LibraryConfig === @config
          @linker_script = nil
        else
          @linker_script = @config.linkerScript.nil? ? nil : @block.convPath(@config.linkerScript)
        end
      end

      def calcArtifactName
        if not @config.artifactName.nil? and @config.artifactName.name != ""
          baseFilename = @config.artifactName.name
          baseFilename += Bake::Toolchain.outputEnding(@block.tcs) if !baseFilename.include?(".")
        else
          baseFilename = "#{@projectName}#{Bake::Toolchain.outputEnding(@block.tcs)}"
        end
        if !@config.artifactExtension.nil? && @config.artifactExtension.name != "default"
          extension = ".#{@config.artifactExtension.name}"
          if baseFilename.include?(".")
            baseFilename = baseFilename.split(".")[0...-1].join(".")
          end
          baseFilename += ".#{@config.artifactExtension.name}"
        end
        @exe_name ||= File.join([@block.output_dir, baseFilename])
        if Bake.options.abs_path_in
          @exe_name = File.expand_path(@exe_name, @projectDir)
        end
        return @exe_name
      end

      def calcCmdlineFile()
        @exe_name + ".cmdline"
      end

      def calcMapFile
        @mapfile = nil
        if Metamodel::LibraryConfig === @config
          def @config.mapFile
            Metamodel::MapFile.new
          end
        end
        if (not Bake.options.docu) and (not @config.mapFile.nil?)
          if @config.mapFile.name == ""
            @mapfile = @exe_name.chomp(File.extname(@exe_name)) + ".map"
          else
            @mapfile = @config.mapFile.name
          end
        end
      end

      def ignore?
        Bake.options.prepro
      end

      def needed?(libs)
        return "because linkOnly was specified" if Bake.options.linkOnly

        # exe
        return "because executable does not exist" if not File.exist?(@exe_name)

        eTime = File.mtime(@exe_name)

        # linkerscript
        if @linker_script
          return "because linker script does not exist - will most probably result in an error" if not File.exist?(@linker_script)
          return "because linker script is newer than executable" if eTime < File.mtime(@linker_script)
        end

        # sources
        @compileBlock.objects.each do |obj|
          return "because object #{obj} does not exist" if not File.exist?(obj)
          return "because object #{obj} is newer than executable" if eTime < File.mtime(obj)
        end if @compileBlock

        # libs
        libs.each do |lib|
          return "because library #{lib} does not exist" if not File.exist?(lib)
          return "because library #{lib} is newer than executable" if eTime < File.mtime(lib)
        end
        false
      end

      def execute
        Dir.chdir(@projectDir) do
          
          subBlocks = @block.bes.select{|d| Metamodel::Dependency === d}.map { |d| ALL_BLOCKS["#{d.name},#{d.config}"] }
          if subBlocks.any? { |d| d.result == false }
            if Bake.options.stopOnFirstError
              Blocks::Block.set_delayed_result
              return true
            else
              return false
            end
          end

          allSources = []
          (subBlocks + [@block]).each do |b|
            Dir.chdir(b.projectDir) do
              b.getCompileBlocks.each do |c|
                srcs = c.calcSources(true, true).map { |s| File.expand_path(s) }
                allSources += srcs
              end
            end
          end
          
          duplicateSources = allSources.group_by{ |e| e }.select { |k, v| v.size > 1 }.map(&:first)
          duplicateSources.each do |d|
            Bake.formatter.printError("Source compiled more than once: #{d}")
          end
          ExitHelper.exit(1) if duplicateSources.length > 0

          libs, linker_libs_array = LibElements.calc_linker_lib_string(@block, @block.tcs)

          cmdLineCheck = false
          cmdLineFile = calcCmdlineFile()

          return true if ignore?
          reason = needed?(libs)
          if not reason
            cmdLineCheck = true
            reason = config_changed?(cmdLineFile)
          end

          linker = @block.tcs[:LINKER]

          cmd = Utils.flagSplit(linker[:PREFIX], true)
          cmd += Utils.flagSplit(linker[:COMMAND], true) # g++
          onlyCmd = cmd

          cmd += linker[:MUST_FLAGS].split(" ")
          cmd += Bake::Utils::flagSplit(linker[:FLAGS],true)
          cmd << linker[:EXE_FLAG]
          if linker[:EXE_FLAG_SPACE]
            cmd << @exe_name
          else
            cmd[cmd.length-1] += @exe_name
          end

          cmd += @compileBlock.objects
          if @linker_script
            if linker[:SCRIPT_SPACE]
              cmd << linker[:SCRIPT] # -T
              cmd << @linker_script # xy/xy.dld
            else
              cmd << linker[:SCRIPT]+@linker_script
            end
          end
          cmd += linker[:MAP_FILE_FLAG].split(" ") if @mapfile # -Wl,-m6
          if not linker[:MAP_FILE_PIPE] and @mapfile
            cmd[cmd.length-1] << @mapfile
          end
          cmd += Bake::Utils::flagSplit(linker[:LIB_PREFIX_FLAGS],true) # "-Wl,--whole-archive "
          cmd += linker_libs_array
          cmd += Bake::Utils::flagSplit(linker[:LIB_POSTFIX_FLAGS],true) # "-Wl,--no-whole-archive "

          realCmd = Bake.options.fileCmd ? calcFileCmd(cmd, onlyCmd, @exe_name, linker) : cmd
            
          # pre print because linking can take much time
          cmdLinePrint = Bake.options.fileCmd ? realCmd.dup : cmd.dup

          # some mapfiles are printed in stdout
          outPipe = (@mapfile and linker[:MAP_FILE_PIPE]) ? "#{@mapfile}" : nil
          cmdLinePrint << "> #{outPipe}" if outPipe

          if cmdLineCheck and BlockBase.isCmdLineEqual?(cmd, cmdLineFile)
            success = true
          else
            ToCxx.linkBlock

            BlockBase.prepareOutput(File.expand_path(@exe_name,@projectDir), @block)

            printCmd(cmdLinePrint, "Linking   #{@projectName} (#{@config.name}): #{@exe_name}", reason, false)
            BlockBase.writeCmdLineFile(cmd, cmdLineFile)
            success = true
            consoleOutput = ""
            retry_linking = Bake.options.dev_features.include?("retry-linking") ? 5 : 1
            begin
              success, consoleOutput = ProcessHelper.run(realCmd, false, false, outPipe) if !Bake.options.dry
              process_result(cmdLinePrint, consoleOutput, linker[:ERROR_PARSER], nil, reason, success)
            rescue Exception
              retry_linking -= 1
              retry if !success && retry_linking > 0
              raise
            end
            check_config_file()
          end

          return success
        end
      end

      def clean
        return cleanProjectDir()
      end

    end

  end
end