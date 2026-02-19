xrotation := "358"
yrotation := "5"
zrotation := "2"
width := "1278"
height := "744"
outdir := "docs"
projectbase := "hardware/ac400.kicad"

[private]
help:
    @just --list export

all: schema images

schema:
    @kicad-cli sch export pdf {{projectbase}}_sch -o {{outdir}}/schematic-v1.pdf

layout:
    @kicad-cli pcb export pdf {{projectbase}}_pcb -o {{outdir}}/layout-front.pdf -l F.Cu,Edge.Cuts --black-and-white
    @kicad-cli pcb export pdf {{projectbase}}_pcb -o {{outdir}}/layout-back.pdf -l B.Cu,Edge.Cuts --black-and-white --mirror
    @kicad-cli pcb export pdf {{projectbase}}_pcb -o {{outdir}}/silkscreen-front.pdf -l F.Silkscreen,Edge.Cuts --black-and-white
    @kicad-cli pcb export pdf {{projectbase}}_pcb -o {{outdir}}/silkscreen-back.pdf -l B.Silkscreen,Edge.Cuts --black-and-white --mirror

[private]
pcb_image zrotation params:
    @kicad-cli pcb render -w {{width}} -h {{height}} {{params}} \
    --perspective --rotate "{{xrotation}},{{yrotation}},{{zrotation}}" \
    --quality high {{projectbase}}_pcb

images:
    @just export pcb_image {{zrotation}} "--output {{outdir}}/board-front.jpg"
    @just export pcb_image -{{zrotation}} "--output {{outdir}}/board-back.jpg --side bottom"
