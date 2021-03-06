#
# Copyright (c) 2018 Kenshi Muto
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'zip'
require 'rexml/document'
require 'cgi'

module ReVIEW
  class Epub2Html
    def self.execute(*args)
      new.execute(*args)
    end

    def execute(*args)
      if args[0].nil? || !File.exist?(args[0])
        STDERR.puts <<EOT
Usage: #{File.basename($PROGRAM_NAME)} EPUBfile [file_for_head_and_foot] > HTMLfile
       file_for_head_and_foot: HTML file to extract header and footer area.
                               This file must be contained in the EPUB.
                               If omitted, the first found file is used.
EOT
        exit 1
      end

      parse_epub(args[0])
      puts join_html(args[1])
    end

    def initialize
      @opfxml = nil
      @htmls = {}
      @head = nil
      @tail = nil
    end

    def parse_epub(epubname)
      Zip::File.open(epubname) do |zio|
        zio.each do |entry|
          if entry.name =~ /.+\.opf\Z/
            opf = entry.get_input_stream.read
            @opfxml = REXML::Document.new(opf)
          elsif entry.name =~ /.+\.x?html\Z/
            @htmls[entry.name.sub('OEBPS/', '')] = entry.get_input_stream.read.force_encoding('utf-8')
          end
        end
      end
      nil
    end

    def take_headtail(html)
      @head = html.sub(/(<body.*?>).*/m, '\1')
      @tail = html.sub(%r{.*(</body>)}m, '\1')
    end

    def sanitize(s)
      s = s.sub(/\.x?html\Z/, '').
          sub(%r{\A\./}, '')
      's_' + CGI.escape(s).
             gsub(/[.,+%]/, '_')
    end

    def modify_html(fname, html)
      doc = REXML::Document.new(html)
      doc.context[:attribute_quote] = :quote

      ids = {}

      doc.each_element('//*[@id]') do |e|
        sid = "#{sanitize(fname)}_#{sanitize(e.attributes['id'])}"
        while ids[sid]
          sid += 'E'
        end
        ids[sid] = true
        e.attributes['id'] = sid
      end

      doc.each_element('//a[@href]') do |e|
        href = e.attributes['href']
        if href.start_with?('http:', 'https:', 'ftp:', 'ftps:', 'mailto:')
          next
        end

        file, anc = href.split('#', 2)
        if anc
          if file.empty?
            anc = "#{sanitize(fname)}_#{sanitize(anc)}"
          else
            anc = "#{sanitize(file)}_#{sanitize(anc)}"
          end
        else
          anc = sanitize(file)
        end

        e.attributes['href'] = "##{anc}"
      end

      doc.to_s.
        sub(/.*(<body.*?>)/m, %Q(<section id="#{sanitize(fname)}">)).
        sub(%r{(</body>).*}m, '</section>')
    end

    def join_html(reffile)
      body = []
      make_list.each do |fname|
        if @head.nil? && (reffile.nil? || reffile == fname)
          take_headtail(@htmls[fname])
        end

        body << modify_html(fname, @htmls[fname])
      end
      "#{@head}\n#{body.join("\n")}\n#{@tail}"
    end

    def make_list
      items = {}
      @opfxml.each_element("/package/manifest/item[@media-type='application/xhtml+xml']") do |e|
        items[e.attributes['id']] = e.attributes['href']
      end

      files = []
      @opfxml.each_element('/package/spine/itemref') do |e|
        files.push(items[e.attributes['idref']])
      end

      files
    end
  end
end
