#include <cuda.h>
#include "filters.h"
#include "kmeans.h"
#include <cutil.h>
#include <stdio.h>

#define TEXTON64 2
#define TEXTON32 1

texture<float, 2, cudaReadModeElementType> image;
texture<float, 1, cudaReadModeElementType> tex_coefficients;


__device__ __constant__ int radii[170]; // can fit upto 10 scales! 

/* __device__ __constant__ float coefficients[9010]; */

/*
__global__ void convolve(int filterCount, int nPixels, int width, int height, float* output) {
  int x = blockDim.x * blockIdx.x + threadIdx.x;
  int y = blockDim.y * blockIdx.y + threadIdx.y;
  if ((x < width) && (y < height)) {
    int coefficientIndex = 0;
    for(int filter = 0; filter < filterCount; filter++) {
      int radius = radii[filter];
      float result = 0.0f;
      for(int compX = x - radius; compX <= x + radius; compX++) {
        for(int compY = y - radius; compY <= y + radius; compY++) {
          result += tex2D(image, compX, compY) * coefficients[coefficientIndex];
          coefficientIndex++;
        }
      }
      output[nPixels * filter + y * width + x] = result;
    }
  }
}
*/

__global__ void convolve(int filterCount, int nPixels, int width, int height, float* output) {
  int x = blockDim.x * blockIdx.x + threadIdx.x;
  int y = blockDim.y * blockIdx.y + threadIdx.y;
  if ((x < width) && (y < height)) {
    int coefficientIndex = 0;
    for(int filter = 0; filter < filterCount; filter++) {
      int radius = radii[filter];
      float result = 0.0f;
      for(int compX = x - radius; compX <= x + radius; compX++) {
        for(int compY = y - radius; compY <= y + radius; compY++) {
          //result += tex2D(image, compX, compY) * coefficients[coefficientIndex];
          result += tex2D(image, compX, compY) * tex1Dfetch(tex_coefficients, coefficientIndex);
          coefficientIndex++;
        }
      }
      output[nPixels * filter + y * width + x] = result;
    }
  }
}


    

void findTextons(int width, int height, float* devImage, int** p_devTextons, int p_nTextonChoice) {
  
  //int filterCount = 34;
  int clusterCount = 32;
  if (p_nTextonChoice == TEXTON64)
      clusterCount = 64;

  int nPixels = width * height;
  float* devResponses;

  float* hCoefficients = 0;
  int* hRadii = 0;
  int nscales = 2;
  float *scales = new float[nscales];
  scales[0] = 2.0;
  scales[1] = 2.0*M_SQRT2;

  int filterCount = 17*nscales;
  int nFilterCoefficients; 

  createTextonFilters(&hCoefficients, &nFilterCoefficients, &hRadii, scales, nscales);

//  float* f = new float[169];
////  f = gaussian_cs_2D(2,2,0,M_SQRT2l, 6,6);
//  gaussian_2D(f,2,2.0/3.0,0,2,false,6,6);
//
//  f = gaussian_2D(2,2.0/3.0, 0, 2, true, 6,6);
//  for(int i=0;i<169;i++)
//  {
//    printf("%f ", hfilters[i]);
//    //printf("%f ", f[i]);
//    if((i+1)%13==0) printf("\n");
//  }
//  delete[] f;

  CUDA_SAFE_CALL(cudaMalloc((void**)&devResponses, sizeof(float)*nPixels*filterCount));
  //CUDA_SAFE_CALL(cudaMemcpyToSymbol(radii, hRadii, sizeof(hRadii)));
  CUDA_SAFE_CALL(cudaMemcpyToSymbol(radii, hRadii, filterCount*sizeof(int)));
  //CUDA_SAFE_CALL(cudaMemcpyToSymbol(coefficients, hCoefficients, sizeof(hCoefficients)));
  //CUDA_SAFE_CALL(cudaMemcpyToSymbol(coefficients, hCoefficients, nFilterCoefficients* sizeof(float)));
  
  float* devcoefficients;
  CUDA_SAFE_CALL(cudaMalloc((void**)&devcoefficients, nFilterCoefficients* sizeof(float)));
  CUDA_SAFE_CALL(cudaMemcpy(devcoefficients, hCoefficients, nFilterCoefficients* sizeof(float), cudaMemcpyHostToDevice));

  cudaChannelFormatDesc channelMax = cudaCreateChannelDesc<float>();
  size_t offset = 0;
  cudaBindTexture(&offset, &tex_coefficients, devcoefficients, &channelMax, nFilterCoefficients*sizeof(float));
  
  cudaArray* imageArray;
  cudaChannelFormatDesc floatTex = cudaCreateChannelDesc<float>();
  CUDA_SAFE_CALL(cudaMallocArray(&imageArray, &floatTex, width, height));
  CUDA_SAFE_CALL(cudaMemcpyToArray(imageArray, 0, 0, devImage, nPixels * sizeof(float), cudaMemcpyDeviceToDevice));
  CUDA_SAFE_CALL(cudaBindTextureToArray(image, imageArray));
  printf("Convolving\n");
  dim3 gridDim = dim3((width - 1)/XBLOCK + 1, (height - 1)/YBLOCK + 1);
  dim3 blockDim = dim3(XBLOCK, YBLOCK);

  convolve<<<gridDim, blockDim>>>(filterCount, nPixels, width, height, devResponses);
  
  kmeans(p_nTextonChoice, nPixels, width, height, clusterCount, filterCount, devResponses, p_devTextons);
 
  CUDA_SAFE_CALL(cudaFreeArray(imageArray));
  CUDA_SAFE_CALL(cudaFree(devResponses));

  free(hRadii);
  free(hCoefficients);

  
}
