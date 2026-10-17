// Generate bounded geographic artwork from Natural Earth's public-domain 50m countries.
// Usage: node scripts/prepare_regional_maps.mjs ne_50m_admin_0_countries.geojson
// Emits Swift data to stdout; no network or private inputs are used.
import {readFileSync} from 'node:fs';
const data = JSON.parse(readFileSync(process.argv[2], 'utf8'));
function simplify(points, tolerance = 0.30) {
  if (points.length <= 2) return points;
  const a=points[0],b=points.at(-1),dx=b[0]-a[0],dy=b[1]-a[1],d=dx*dx+dy*dy;
  let farthest=0,index=0;
  for(let i=1;i<points.length-1;i++) {
    const p=points[i],t=d ? Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/d)) : 0;
    const distance=Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy);
    if(distance>farthest) { farthest=distance;index=i; }
  }
  return farthest>tolerance ? [...simplify(points.slice(0,index+1),tolerance).slice(0,-1),...simplify(points.slice(index),tolerance)] : [a,b];
}
function edges(region) {
  const result=[];
  const inside=region==='northAmerica' ? p=>p[0]>=-170&&p[0]<=-49&&p[1]>=8&&p[1]<=85 : p=>p[0]>=-25&&p[0]<=45&&p[1]>=34&&p[1]<=72;
  for(const f of data.features) {
    if(region==='northAmerica' ? f.properties.CONTINENT!=='North America' : f.properties.CONTINENT!=='Europe' && !['Turkey','Cyprus'].includes(f.properties.ADMIN)) continue;
    const polygons=f.geometry.type==='MultiPolygon'?f.geometry.coordinates:[f.geometry.coordinates];
    for(const polygon of polygons) {
      const ring=polygon[0],half=Math.floor(ring.length/2);
      const area=Math.abs(ring.slice(1).reduce((sum,p,i)=>sum+ring[i][0]*p[1]-p[0]*ring[i][1],0))/2;
      if(area<0.25) continue;
      const points=[...simplify(ring.slice(0,half+1)).slice(0,-1),...simplify(ring.slice(half))];
      for(let i=1;i<points.length;i++) {
        if(inside(points[i-1])&&inside(points[i])&&Math.abs(points[i][0]-points[i-1][0])<180)
          result.push([...points[i-1],...points[i]].map(x=>Number(x.toFixed(4))));
      }
    }
  }
  return result;
}
if (process.argv[3]) {
  const values=edges(process.argv[3]);
  if(process.argv[4]==='count') { console.log(values.length); process.exit(0); }
  const start=Number(process.argv[4]??0),end=start+Number(process.argv[5]??values.length);
  console.log(values.slice(start,end).map(e=>'        SIMD4('+e.join(', ')+'),').join('\n'));
  process.exit(0);
}
console.log('// Public-domain Natural Earth 50m admin-0 country artwork, simplified to 0.30 degrees.\n// Default de facto boundaries; clipped regional coverage; not a navigation/boundary authority.\n// https://www.naturalearthdata.com/about/terms-of-use/\n// Regenerate with scripts/prepare_regional_maps.mjs and ne_50m_admin_0_countries.geojson.\nenum RegionalMapData {\n'+['northAmerica','europe'].map(region=>'    static let '+region+': [SIMD4<Float>] = [\n'+edges(region).map(e=>'        SIMD4('+e.join(', ')+'),').join('\n')+'\n    ]').join('\n')+'\n}');
