#!/usr/bin/env ruby
#
#  Copyright (C) 2008 Elan Feingold (elan at bluemandrill dot com)
#
#  This Program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2, or (at your option)
#  any later version.
#
#  This Program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with GNU Make; see the file COPYING.  If not, write to
#  the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
#  http://www.gnu.org/copyleft/gpl.html
#
#
require 'bit-struct'

# For example, "_calloc" => "_wrap_calloc"
prefix = '___wrap_'
mappings = {
  'calloc' => true, 'malloc' => true, 'realloc' => true, 'free' => true, 'open' => true, 'open64' => true,
  'close' => true, 'write' => true, 'read' => true, 'lseek' => true, 'lseek64' => true, 'fclose' => true,
  'ferror' => true, 'clearerr' => true, 'feof' => true, 'fileno' => true, 'fopen' => true,'fdopen' => true,
  'freopen' => true,'fread' => true,'fwrite' => true, 'fflush' => true, 'fputc' => true,'fputs' => true,
  'putc' => '___wrap__IO_putc', 'fseek' => true,'ftell' => true,'rewind' => true, 'fgetpos' => true,
  'fsetpos' => true, 'fprintf' => true, 'vfprintf' => true, 'fgetc' => true, 
  'fgets' => true, 'getc' => '___wrap__IO_getc', 'ungetc' => true, 'ioctl' => true, 'stat' => true, 'printf' => true, 
}

prefix_python = '___py_wrap_'
mappings_python = {
  'fopen64' => true, 'getcwd' => true, 'chdir' => true, 'access' => true, 'unlink' => true, 'chmod' => true, 
  'rmdir' => true, 'utime' => true, 'rename' => true, 'mkdir' => true, 'open' => true, 'fopen' => true, 
  'freopen' => true, 'opendir' => true, 'dlopen' => true, 'dlclose' => true, 'dlsym' => true,
  'lstat' => true, 'stat' => true
}

LC_SYMTAB = 0x02
LC_SEGMENT = 0x01

class MachHeader < BitStruct
  hex_octets  :magic,       32, "Magic Number"
  unsigned    :cputype,     32, "CPU Type", :endian => :little
  unsigned    :cpusubtype,  32, "CPU Subtype", :endian => :little
  unsigned    :filetype,    32, "File Type", :endian => :little
  unsigned    :ncmds,       32, "Number of commands", :endian => :little
  unsigned    :sizeofcmds,  32, "Size of commands", :endian => :little
  unsigned    :flags,       32, "Flags", :endian => :little
  rest        :data,            "Data"
end

class LoadCommand < BitStruct
  unsigned    :cmd,         32, "Command", :endian => :little
  unsigned    :cmdsize,     32, "Command Size", :endian => :little
end

class SymtabCommand < BitStruct
  unsigned    :cmd,         32, "Command", :endian => :little
  unsigned    :cmdsize,     32, "Command Size", :endian => :little
  unsigned    :symoff,      32, "Symbol Offset", :endian => :little
  unsigned    :nsyms,       32, "Number of Symbols", :endian => :little
  unsigned    :stroff,      32, "String table offset", :endian => :little
  unsigned    :strsize,     32, "Size of string table", :endian => :little
end

class SegmentCommand < BitStruct
  unsigned    :cmd,         32, "Command", :endian => :little
  unsigned    :cmdsize,     32, "Command Size", :endian => :little
  char        :segname,    16*8, "Segment name", :endian => :little
  unsigned    :vmaddr,      32, "VM Adddress", :endian => :little
  unsigned    :vmsize,      32, "VM Size", :endian => :little
  unsigned    :fileoff,     32, "File Offset", :endian => :little
  unsigned    :filesize,    32, "File Size", :endian => :little
end

class SymtabEntry < BitStruct
  unsigned  :strtableoffset, 32, "String table offset", :endian => :little
  unsigned  :debuggingEntry,  3, "Debugging entry", :endian => :little
  unsigned  :privateExternal, 1, "Is Private Enternal", :endian => :little
  unsigned  :type,            3, "Type bits", :endian => :little
  unsigned  :external,        1, "External symbol", :endian => :little
  unsigned  :sectionNumber,   8, "Section number", :endian => :little
  unsigned  :description,    16, "Description", :endian => :little
  unsigned  :value,          32, "Value", :endian => :little
end

# Select which mapping to use.
if ARGV.size() > 1 and ARGV[1].index('libpython') == 0
  puts "Using Python mappings."
  mappings = mappings_python
  prefix = prefix_python
end

data = open(ARGV[0]).read
puts "Input file was #{data.length} bytes long."

# Parse the header.
header = MachHeader.new(data)
sym_cmd = nil

# String table.
string_table = nil
string_table_offset = nil
string_table_map = {}
offset_map = {}

# Symbol table.
symbol_table = nil
symbol_table_offset = nil
symbols = []

# Link segment.
link_cmd = nil
link_cmd_offset = nil

# Walk through all the commands.
offset = data.size - header.data.size
header.ncmds.times do |i|
  load_cmd = LoadCommand.new(data[offset..-1])
  
  if load_cmd.cmd == LC_SEGMENT
    seg_cmd = SegmentCommand.new(data[offset..-1])
    if seg_cmd.segname.index('__LINKEDIT') == 0
      puts "Found LINKEDIT segment at offset #{offset}"
      link_cmd = seg_cmd
      link_cmd_offset = offset
    end
  end
  
  if load_cmd.cmd == LC_SYMTAB
    # Parse the symbol table command.
    sym_cmd = SymtabCommand.new(data[offset..-1])
    symbol_table_offset = offset
    
    # Parse the string table, store with offsets.
    string_table_offset = sym_cmd.stroff
    string_table = data[sym_cmd.stroff..sym_cmd.stroff+sym_cmd.strsize-1]
    i = 0
    string_table.split("\x00", -1).each do |s|
      string_table_map[i] = s
      i += s.length + 1
    end
    
    # Parse the symbol table.
    symbol_table = data[sym_cmd.symoff..-1]
    i = 0
    puts "Symbol table has #{sym_cmd.nsyms} symbols."
    sym_cmd.nsyms.times do |n|
      symbols << SymtabEntry.new(symbol_table[i..i+11])
      i += 12
    end
    
    # Now go through and make renames to the symbols.
    size_diff = 0
    
    string_table_map.keys.sort.each do |i|
      orig_sym = string_table_map[i]
      
      # Store the offset mapping.
      offset_map[i] = (i + size_diff)
      
      if orig_sym.length > 1
        sym = orig_sym[1..-1].gsub('$UNIX2003','')
        if mappings.has_key?(sym)
          if mappings[sym] != true
            string_table_map[i] = mappings[sym]
          else
            string_table_map[i] = "#{prefix}#{sym}"
          end
          puts "   - Mapping: #{orig_sym} to #{string_table_map[i]} (offset #{i} -> #{i + size_diff})"
                          
          # Accumulate the offset difference.
          size_diff += string_table_map[i].length - orig_sym.length
        end
      end
    end
  end
  
  offset += load_cmd.cmdsize
end

# OK, now lets rewrite the symbol table. Offsets may have changed, but the size doesn't.
new_symbol_table = ''
i = 0
symbols.each do |symbol|
  puts "  - Mapped #{i} symbols..." if i % 10000 == 0 and i > 0
  symbol.strtableoffset = offset_map[symbol.strtableoffset] if symbol.strtableoffset > 1
  new_symbol_table << symbol
  i += 1
end

# OK, now lets rewrite the string table. The size will be different if mappings have occurred.
new_string_table = string_table_map.keys.sort.collect { |i| string_table_map[i] }.join("\x00")

# Next, modify the LC_SYMTAB header.
size_diff = new_string_table.length - sym_cmd.strsize
sym_cmd.strsize = new_string_table.length

# Lastly, modify the LINKEDIT segment if it exists.
if link_cmd
  puts "Size changed by #{size_diff} bytes, rewriting LINKEDIT segment."
  link_cmd.filesize += size_diff
  SegmentCommand.round_byte_length.times { |i| data[link_cmd_offset + i] = link_cmd[i] }
end

# Create the new file in memory. First, copy the new symbol table header into place.
24.times { |i| data[symbol_table_offset + i] = sym_cmd[i] }

# Now copy the new symbol table.
new_symbol_table.length.times { |i| data[sym_cmd.symoff + i] = new_symbol_table[i] }

# Finally, add the new string table.
data = data[0..string_table_offset-1] + new_string_table

puts "Output file is #{data.length} bytes long."
open("output.so", "wb").write(data)
