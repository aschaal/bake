require_relative '../../bake/model/loader'
require_relative '../../bake/config/loader'
require_relative '../../bake/config/checks'

module Bake

  class AdaptConfig
    attr_reader :referencedConfigs

    @@filenames = []

    def self.filenames
      @@filenames
    end

    def loadProjMeta(filename, filenum)

      Bake::Configs::Checks.symlinkCheck(filename)
      Bake::Configs::Checks.sanityFolderName(filename)

      f = @loader.load(filename)

      if f.root_elements.any? { |re| ! Metamodel::Adapt === re }
        Bake.formatter.printError("Config file must have only 'Adapt' elements as roots", filename)
        ExitHelper.exit(1)
      end

      f.root_elements.each do |a|
        Bake::Config::checkVer(a.requiredBakeVersion)
      end

      configs = []
      f.root_elements.each { |re| configs.concat(re.getConfig) }
      AdaptConfig::checkSyntax(configs, filename)
      configs
    end

    def self.checkSyntax(configs, filename, isLocalAdapt = false)
      Bake::Configs::Checks::commonMetamodelCheck(configs, filename, true)
      configs.each do |c|
        if not c.extends.empty?
          Bake.formatter.printError("Attribute 'extends' must not be used in adapt config.",c)
          ExitHelper.exit(1)
        end
        if c.name.empty?
          Bake.formatter.printError("Configs must be named.",c)
          ExitHelper.exit(1)
        end
        if c.project.empty?
          Bake.formatter.printError("The corresponding project must be specified.",c)
          ExitHelper.exit(1)
        end if !isLocalAdapt
        if not ["replace", "remove", "extend", "push_front"].include?c.type
          Bake.formatter.printError("Allowed types are 'replace', 'remove', 'extend' and 'push_front'.",c)
          ExitHelper.exit(1)
        end
        if not ["", "yes", "no", "all"].include?c.mergeInc
          Bake.formatter.printError("Allowed modes are 'all', 'yes', 'no' and unset.",c)
          ExitHelper.exit(1)
        end
      end
    end

    def getPotentialAdaptionProjects()
      potentialAdapts = []
      Bake.options.roots.each do |root|
        r = root.dir
        if (r.length == 3 && r.include?(":/"))
          r = r + Bake.options.main_project_name # glob would not work otherwise on windows (ruby bug?)
        end
        Bake.options.adapt.each do |a|
          adaptBaseName = File.expand_path(a.gsub(/\(.*\)/,"") + "/Adapt.meta")
          potentialAdapts << adaptBaseName  if File.exist?adaptBaseName
        end
        potentialAdapts.concat(Root.search_to_depth(r, "Adapt.meta", root.depth))
      end

      potentialAdapts.uniq
    end

    def chooseProjectFilenames(potentialAdapts)
      @@filenames = []
      Bake.options.adapt.each do |aComplete|
        aComplete.gsub!(/\\/,"/")
        a = aComplete.gsub(/\[.*\]/,"")
        projFilter = aComplete.scan(/\[(.*)\]/)
        if projFilter && projFilter.length > 0
          projFilter = projFilter[0][0].split(";").map {|a| a.strip}
        end

        found = false

        # from working dir
        if File.exist?(a) && File.file?(a)
          @@filenames << {:file => File.expand_path(a), :projs => projFilter}
          found = true
        end
        next if found

        # from main dir
        Dir.chdir Bake.options.main_dir do
          if File.exist?(a) && File.file?(a)
            @@filenames << {:file => (Bake.options.main_dir + "/" + a), :projs => projFilter}
            found = true
          end
        end
        next if found

        # from roots
        Bake.options.roots.each do |root|
          r = root.dir
          Dir.chdir r do
            if File.exist?(a) && File.file?(a)
              @@filenames << {:file => (r + "/" + a), :projs => projFilter}
              found = true
            end
          end
          break if found
        end
        next if found

        # old style
        adapts = potentialAdapts.find_all { |p| p.include?("/"+a+"/Adapt.meta") or p == a+"/Adapt.meta" }
        if adapts.empty?
          Bake.formatter.printError("Adaption project #{a} not found")
          ExitHelper.exit(1)
        else
          @@filenames << {:file => adapts[0], :projs => projFilter}
          if (adapts.length > 1)
            Bake.formatter.printWarning("Adaption project #{a} exists more than once")
            chosen = " (chosen)"
            adapts.each do |f|
              Bake.formatter.printWarning("  #{File.dirname(f)}#{chosen}")
              chosen = ""
            end
          end
        end
      end

    end

    def load()
      @@filenames = []
      return [] if Bake.options.adapt.empty?

      @loader = Loader.new

      potentialProjects = getPotentialAdaptionProjects()
      chooseProjectFilenames(potentialProjects)

      configs = []
      @@filenames.each_with_index do |f,i|
        loadProjMeta(f[:file], i+1).each do |c|
          configs << {:config => c, :projs => f[:projs]}
        end
      end

      return configs
    end


  end

end
