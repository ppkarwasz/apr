# Makefile for source rpm: apr
# $Id: Makefile,v 1.1 2004/09/09 03:02:15 cvsdist Exp $
NAME := apr
SPECFILE = $(firstword $(wildcard *.spec))
UPSTREAM_CHECKS = asc

include ../common/Makefile.common
