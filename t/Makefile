#!/usr/bin/make

all:
	cp testopf-missingfwid.xml test1.opf
	cp testopf-emptyuid.xml test2.opf
	opffix test1.opf	
	opffix test2.opf

clean:
	rm -f test1.opf test2.opf emptyuid.opf missingfwid.opf toc.ncx

