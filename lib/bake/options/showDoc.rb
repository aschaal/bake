module Bake
  class Doc
    def self.show

      link = "http://esrlabs.github.io/bake"
      if RUBY_PLATFORM =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RUBY_PLATFORM =~ /darwin/
        system "open #{link}"
      elsif RUBY_PLATFORM =~ /linux|bsd/
        system "xdg-open #{link}"
      else
        puts "Please open #{link} manually in your browser."
      end

      ExitHelper.exit(0)
    end

  end
end
