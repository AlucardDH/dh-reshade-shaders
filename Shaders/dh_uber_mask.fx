////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_MASK 0.1.0
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

// Depth mask
    uniform bool bDepthMask <
        ui_category = "Depth mask";
        ui_label = "Enable";
    > = true;


    uniform float fDepthMaskMin <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Min";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.10;


    uniform float fDepthMaskMax <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Max";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 1.0;

    uniform float fDepthMaskStrength <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Strength";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.5;

// Brightness mask

    uniform bool bBrightnessMask <
        ui_category = "Brightness mask";
        ui_label = "Enable";
    > = true;
    

    uniform float fBrightnessMaskMin <
        ui_type = "slider";
        ui_category = "Brightness mask";
        ui_label = "Min";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.6;


    uniform float fBrightnessMaskMax <
        ui_type = "slider";
        ui_category = "Brightness mask";
        ui_label = "Max";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 1.0;

    uniform float fBrightnessMaskStrength <
        ui_type = "slider";
        ui_category = "Brightness mask";
        ui_label = "Strength";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.65;


// PS

    void PS_Save(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        outColor = getColor(coords);
    }

    float computeMask(float value, float minV, float maxV, float strength) {
        if(value<minV) {
            return 0.0;
        }
        if(value>maxV) {
            return strength;
        }
        float normalizedValue = (value-minV)/(maxV-minV);
        return normalizedValue * strength;
    }

    void PS_Apply(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        float4 afterColor = getColor(coords);
        float4 beforeColor = getColorSampler(beforeSampler,coords);

        float mask = 0.0;
        if(bDepthMask) {
            float value = ReShade::GetLinearizedDepth(coords);
            mask += computeMask(value,fDepthMaskMin,fDepthMaskMax,fDepthMaskStrength);
        }

        if(bBrightnessMask) {
            float value = maxOf3(beforeColor.rgb);
            mask += computeMask(value,fBrightnessMaskMin,fBrightnessMaskMax,fBrightnessMaskStrength);
        }

        outColor = lerp(beforeColor,afterColor,1.0-saturate(mask));
    }


// TEHCNIQUES 
    
    technique DH_UBER_MASK_BEFORE {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Save;
            RenderTarget = beforeTex;
        }
    }

    technique DH_UBER_MASK_AFTER {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Apply;
        }
    }

}