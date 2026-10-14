// Convert Natural Earth's public-domain 110m land polygons into bounded coastlines.
// Input: ne_110m_land.geojson from nvkelso/natural-earth-vector. Output: Swift source.
import { readFileSync } from 'node:fs';
const data = JSON.parse(readFileSync(process.argv[2], 'utf8'));
function simplify(points, tolerance = 0.75) {
  if (points.length <= 2) return points;
  const a = points[0], b = points.at(-1);
  const dx = b[0]-a[0], dy = b[1]-a[1], d = dx*dx+dy*dy;
  let farthest = 0, index = 0;
  for (let i=1; i<points.length-1; i++) {
    const p=points[i], t=d ? Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/d)) : 0;
    const distance=Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy);
    if(distance>farthest) { farthest=distance; index=i; }
  }
  return farthest > tolerance ? [...simplify(points.slice(0,index+1),tolerance).slice(0,-1),...simplify(points.slice(index),tolerance)] : [a,b];
}
const edges=[];
for(const feature of data.features) {
  const polygons=feature.geometry.type==='MultiPolygon' ? feature.geometry.coordinates : [feature.geometry.coordinates];
  for(const polygon of polygons) {
    const ring=polygon[0];
    const area=Math.abs(ring.slice(1).reduce((s,p,i)=>s+ring[i][0]*p[1]-p[0]*ring[i][1],0))/2;
    if(area<6) continue;
    // Split closed rings into two open arcs so RDP keeps each continent's extent.
    const half=Math.floor(ring.length/2);
    const points=[...simplify(ring.slice(0,half+1)).slice(0,-1),...simplify(ring.slice(half))];
    for(let i=1;i<points.length;i++) {
      if(Math.abs(points[i][0]-points[i-1][0])>180) continue;
      edges.push([...points[i-1],...points[i]].map(x=>Number(x.toFixed(3))));
    }
  }
}
console.log('// Made with Natural Earth. Public-domain 110m land data, simplified to 0.75 degrees.\n// https://www.naturalearthdata.com/about/terms-of-use/\n// Regenerate using scripts/prepare_globe_data.mjs with ne_110m_land.geojson.\nenum GlobeCoastlines {\n    static let degrees: [SIMD4<Float>] = [\n'+edges.map(e=>'        SIMD4('+e.join(', ')+'),').join('\n')+'\n    ]\n}');
