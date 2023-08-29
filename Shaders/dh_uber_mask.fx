////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_MASK 0.3.1
//
// This shader is free, if you paid for it, you have been ripped and should ask for a refund.
//
// This shader is developed by AlucardDH (Damien Hembert)
//
// Get more here : https://github.com/AlucardDH/dh-reshade-shaders
//
////////////////////////////////////////////////////////////////////////////////////////////////
#include "Reshade.fxh"


// MACROS /////////////////////////////////////////////////////////////////
// Don't touch this
#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4(c,0,0))
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4(c.xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4(c.xy,0,0))
#define maxOf3(a) max(max(a.x,a.y),a.z)
#define minOf3(a) min(min(a.x,a.y),a.z)
#define avgOf3(a) ((a.x+a.y+a.z)/3.0)
//////////////////////////////////////////////////////////////////////////////

namespace DH_UBER_MASK {

// Textures
    texture beforeTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler beforeSampler { Texture = beforeTex; };


// Parameters    
    /*
    uniform float fTest <
        ui_type = "slider";
        ui_min = 0.0; ui_max = 10.0;
        ui_step = 0.001;
    > = 0.001;
    uniform bool bTest = true;
    uniform bool bTest2 = true;
    uniform bool bTest3 = true;
    */
    
    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0Full Mask\0Mask overlay\0";
        ui_tooltip = "Debug the intermediate steps of the shader";
    > = 0;

// Depth mask

    uniform float3 fDepthMaskNear <
        ui_text = "Center/Range/Strength:";
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Near";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float3(0.0,0.5,0.0);
    
    uniform float3 fDepthMaskMid <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Mid";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float3(0.5,0.5,0.0);

    uniform float3 fDepthMaskFar <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Far";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float3(1.0,0.5,0.5);

// Brightness mask

    uniform float3 fBrightnessMaskDark <
        ui_text = "Center/Range/Strength:";
        ui_type = "slider";
        ui_category = "Brightness mask";
        ui_label = "Dark";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float3(0.0,0.5,0.1);

    uniform float3 fBrightnessMaskMid <
        ui_type = "slider";
        ui_category = "Brightness mask";
        ui_label = "Mid";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float3(0.5,0.25,0.25);

    uniform float3 fBrightnessMaskBright <
        ui_type = "slider";
        ui_category = "Brightness mask";
        ui_label = "Bright";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float3(1.0,0.5,0.75);
    
    uniform int iBrightnessMethod <
        ui_type = "combo";
        ui_category = "Brightness mask";
        ui_label = "Method";
        ui_items = "Max\0Avg\0Min\0";
        ui_min = 0; ui_max = 2;
        ui_step = 1;
        ui_tooltip = "";
    > = 0;
    
// Difference mask

    uniform float2 fDiffMask <
        ui_text = "Range/Strength:";
        ui_type = "slider";
        ui_category = "Difference mask";
        ui_label = "Difference";
        ui_min = 0.0; ui_max = 2.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = float2(1.0,1.0);
    
    uniform int iDiffMethod <
        ui_type = "combo";
        ui_category = "Difference mask";
        ui_label = "Method";
        ui_items = "Max\0Avg\0Min\0";
        ui_min = 0; ui_max = 2;
        ui_step = 1;
        ui_tooltip = "";
    > = 0; 


// PS

    void PS_Save(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        outColor = getColor(coords);
    }
    
    float computeMask(float value, float3 params) {
    	if(value<=params[0]) {
    		return smoothstep(params[0]-params[1],params[0],value)*params[2];
    	} else {
    		return (1.0-smoothstep(params[0],params[0]+params[1],value))*params[2];
    	}
    }
    
    float getBrightness(float3 color) {
    	if(iBrightnessMethod==0) {
    		return maxOf3(color);
    	}
    	if(iBrightnessMethod==1) {
    		return avgOf3(color);
    	}
    	return minOf3(color);
    }
    
    float getDifference(float3 before,float3 after) {
    	float3 diff = abs(before-after);
    	if(iDiffMethod==0) {
    		return maxOf3(diff);
    	}
    	if(iDiffMethod==1) {
    		return avgOf3(diff);
    	}
    	return minOf3(diff);
    }

    void PS_Apply(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        float4 afterColor = getColor(coords);
        float4 beforeColor = getColorSampler(beforeSampler,coords);

        float mask = 0.0;
        
        float depth = ReShade::GetLinearizedDepth(coords);
        mask += computeMask(depth,fDepthMaskNear);
        mask += computeMask(depth,fDepthMaskMid);
        mask += computeMask(depth,fDepthMaskFar);

        float brightness = getBrightness(beforeColor.rgb);
        mask += computeMask(brightness,fBrightnessMaskDark);
        mask += computeMask(brightness,fBrightnessMaskMid);
        mask += computeMask(brightness,fBrightnessMaskBright);
        
        float diff = saturate(getDifference(beforeColor.rgb,afterColor.rgb)*2.0);
        mask += computeMask(diff,float3(1.0,fDiffMask));

		mask = saturate(mask);
		if(iDebug==1) {
        	outColor = float4(mask,mask,mask,1.0);
		} else if(iDebug==2) {
        	outColor = lerp(afterColor,float4(0,1,0,1),mask);
		} else {
        	outColor = lerp(beforeColor,afterColor,1.0-mask);
        }
    }


// TEHCNIQUES 
    
    technique DH_UBER_MASK_BEFORE<
        ui_label = "DH_UBER_MASK 0.3.1 BEFORE";
    > {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Save;
            RenderTarget = beforeTex;
        }
    }

    technique DH_UBER_MASK_AFTER<
        ui_label = "DH_UBER_MASK 0.3.1 AFTER";
    > {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Apply;
        }
    }

}