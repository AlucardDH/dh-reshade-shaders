#include "Reshade.fxh"
uniform int random < source = "random"; min = 0; max = BUFFER_WIDTH*BUFFER_HEIGHT; >;
uniform int iRadius <ui_type = "slider"; ui_label = "Radius"; ui_min = 1; ui_max = 64; ui_step = 1;> = 8;
uniform int iSamples <ui_type = "slider"; ui_label = "Samples count (x4)"; ui_min = 1; ui_max = 64; ui_step = 1;> = 4;
float randomValue(inout uint seed) {seed = seed * 747796405 + 2891336453;
    								uint result = ((seed>>((seed>>28)+4))^seed)*277803737;
    								return ((result>>22)^result)/4294967295.0;}
void PS_AhOh(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target) {
	float3 coordsInt = float3(coords * int2(BUFFER_WIDTH,BUFFER_HEIGHT),ReShade::GetLinearizedDepth(coords));
	int seed = (coordsInt.x+coordsInt.y*BUFFER_WIDTH+random)%(BUFFER_WIDTH*BUFFER_HEIGHT); 
	float3 R = 0;
	for(int step=1;step<=iSamples;step++) {
		float dir = randomValue(seed)*3.14159265359*0.5;
		float2 delta = float2(cos(dir),sin(dir))*iRadius*step*step*(0.5+0.5*randomValue(seed))/iSamples;
		float2 currentCoords = float2(coordsInt.xy+delta)/float2(BUFFER_WIDTH,BUFFER_HEIGHT);
		R += int(ReShade::GetLinearizedDepth(currentCoords)>coordsInt.z);
		currentCoords = float2(coordsInt.xy-delta)/float2(BUFFER_WIDTH,BUFFER_HEIGHT);
		R += int(ReShade::GetLinearizedDepth(currentCoords)>coordsInt.z);
		currentCoords = float2(coordsInt.xy+float2(-delta.y,delta.x))/float2(BUFFER_WIDTH,BUFFER_HEIGHT);
		R += int(ReShade::GetLinearizedDepth(currentCoords)>coordsInt.z);
		currentCoords = float2(coordsInt.xy-float2(-delta.y,delta.x))/float2(BUFFER_WIDTH,BUFFER_HEIGHT);
		R += int(ReShade::GetLinearizedDepth(currentCoords)>coordsInt.z);
	}
	outPixel = float4(ReShade::GetLinearizedDepth(coords)>0.999 ? 1: saturate(0.5+R/(4*iSamples)),1);
}
technique DH_AhOh <> {pass {VertexShader = PostProcessVS; PixelShader = PS_AhOh;}}