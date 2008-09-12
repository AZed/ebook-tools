#! /usr/bin/python

'''A simple converter of Open Ebook Publications to EPUB format'''

__copyright__ = '''\
Copyright (C) 2007 Mikhail Sobolev <mss@mawhrin.net>. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.  THE SOFTWARE IS PROVIDED "AS
IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE
AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.'''

import sys, os, time
from optparse import OptionParser

import zipfile

__container__ = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/%s" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''

class EPubFile:
    '''A simple class for creating .epub files'''

    def __init__(self, name):
        ''' '''
        self.epub = zipfile.ZipFile(name, 'w')
        self.add_data('application/epub+zip', '', 'mimetype', zipfile.ZIP_STORED)

    def __del__(self):
        ''' '''
        self.close()

    def close(self):
        ''' '''
        if self.epub is not None:
            self.epub.close()
            self.epub = None

    def add_file(self, fullname, subdir, relative_name):
        '''Add a content of the specified file to the EPUB'''
        self.epub.write(fullname, os.path.join(subdir, relative_name))

    def add_data(self, data, subdir, relative_name, compression = zipfile.ZIP_DEFLATED):
        '''Add the specified data to the EPUB'''
        zinfo = zipfile.ZipInfo(filename=os.path.join(subdir, relative_name), date_time=time.localtime(time.time()))
        zinfo.compress_type = compression
        self.epub.writestr(zinfo, data)

class OEBFiles:
    '''A class to work Open Ebook Publications'''

    def __init__(self, dirname):
        '''constructor
dirname: string
    directory where a OEB is expected'''

        assert os.path.isdir(dirname), 'You must specify an existing directory name'

        if dirname[-1] == os.path.sep:
            self.dirname = dirname[:-1]
        else:
            self.dirname = dirname

        self._names = []
        self._relname = len(self.dirname) + 1

        os.path.walk(self.dirname, self.add_dir, None)

    def names(self):
        '''return a list of file names that are relevant for this OEB publication'''
        return self._names

    def add_dir(self, dummy, dirname, files):
        '''add the files in the specified directory to the list of relevant files'''
        assert dirname.startswith(self.dirname)

        relname = dirname[self._relname:]

        self._names.extend([ (os.path.join(dirname, filename), os.path.join(relname, filename)) for filename in files if os.path.isfile(os.path.join(dirname, filename))])

def main():
    '''the actual worker :)'''

    parser = OptionParser(usage = '%prog [options] oebdir [epubfilename]')

    # options, args = parser.parse_args()
    args = parser.parse_args()[1]

    if len(args) < 1 or not os.path.isdir(args[0]):
        parser.print_usage()
        sys.exit(1)

    if len(args) == 1:
        outname = args[0]
        if outname[-1] == os.path.sep:
            outname = outname[:-1]

        outname += '.epub'
    else:
        outname = args[1]

    oebfiles = OEBFiles(args[0])

    opfs = [ itsname for dummy, itsname in oebfiles.names() if itsname.endswith('.opf') ]

    if len(opfs) == 0:
        print >> sys.stderr, 'No .opf files found'
        sys.exit(2)
    elif len(opfs) != 1:
        print >> sys.stderr, 'Found too many .opf files:', opfs
        sys.exit(3)

    epub = EPubFile(outname)

    epub.add_data(__container__ % opfs[0], 'META-INF', 'container.xml')

    for realfile, itsname in oebfiles.names():
        epub.add_file(realfile, 'OEBPS', itsname)

    epub.close()
    epub = None

if __name__ == '__main__':
    main()

# vim:ts=4:sw=4:et
