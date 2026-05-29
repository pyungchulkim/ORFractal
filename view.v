/* NOTE: DO NOT ADD COMMENTS AT THE END OF A VALID CONTROL.
 * IT WILL CAUSE A PARSING ERROR.
 */
corrected rotation: on
z buffer: on
concave polygons: on

/* For some reason, the contour sides get trimmed at higher number
 * when line style is pixel or polygon. Maybe, contour info gets fully
 * populated only when line style is cylinder.
 */
line style: cylinder
render mode: shaded
projection: parallel