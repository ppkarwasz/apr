# Makefile for source rpm: apr
# $Id$
NAME := apr
SPECFILE = $(firstword $(wildcard *.spec))

include ../common/Makefile.common
