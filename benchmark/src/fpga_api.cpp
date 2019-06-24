#include "fpga_api.h"
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <cstring>

#define min(x, y) (((x) < (y)) ? (x) : (y))

#define SIZE 64

FPGA::FPGA(off_t data_addr, off_t output_addr, int m_size, int v_size)
{
  m_size_ = m_size;
  v_size_ = v_size/4;
  data_size_ = (m_size_ + 1) * (v_size_/4) * sizeof(int); // fpga bram data size

  fd_ = open("/dev/mem", O_RDWR);
  qdata_ = static_cast<int *>(mmap(NULL, data_size_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, data_addr));
  output_ = static_cast<unsigned int *>(mmap(NULL, sizeof(unsigned int), PROT_READ | PROT_WRITE, MAP_SHARED, fd_, output_addr));
 
  num_block_call_ = 0;
}

FPGA::~FPGA()
{
  munmap(qdata_, data_size_);
  munmap(output_, sizeof(unsigned int));
  close(fd_);
}

int *FPGA::qmatrix(void)
{
  return qdata_ + v_size_;
}

int *FPGA::qvector(void)
{
  return qdata_;
}

void FPGA::reset(void)
{
  num_block_call_ = 0;
}

int FPGA::num_block_call(void)
{
  return num_block_call_;
}

void quantize(const float* input, int* quantized, int num_input, int bits_min, int bits_max, int offset, float scale)
{
  for(int i = 0; i < num_input; i++)
  {
    quantized[i/4] += (int)(input[i] / scale) << (8*(i%4));// + (float)offset; // TODO: convert floating point to quantized value
  }
}

void dequantize(int* quantized, float* output, int num_output, int offset, float scale)
{
  for(int i = 0; i < num_output; i++)
  {
    output[i] = scale * (quantized[i] - offset) ; // TODO: convert quantized value to floating point
  }
}

const int *__attribute__((optimize("O0"))) FPGA::qblockMV(Compute* comp)
{
  num_block_call_ += 1;

  // fpga version
  *output_ = 0x5555;
  while (*output_ == 0x5555)
    ;

  return qdata_;
}

void FPGA::largeMV(const float *large_mat, const float *input, float *output, int num_input, int num_output, Compute* comp)
{
  int *vec = this->qvector();
  int *mat = this->qmatrix();

  int *qlarge_mat = new int[((num_input-1)/4+1)*num_output]();
  int *qinput = new int[(num_input-1)/4+1]();
  int *qoutput = new int[num_output]();

  // quantize
  int act_bits_min = 0;
  int act_bits_max = (1<<(comp->act_bits-1))-1;

    float act_scale = ((float)comp->act_max - (float)comp->act_min) / (float)act_bits_max; // TODO calculate the scale factor

    int act_offset = 0;

  quantize(input, qinput, num_input, act_bits_min, act_bits_max, act_offset, act_scale);

  int weight_bits_min = 0;
  int weight_bits_max = (1<<(comp->weight_bits-1))-1;

    float weight_scale = ((float)comp->weight_max - (float)comp->weight_min) / (float)weight_bits_max; // TODO calculate the scale factor

    int weight_offset = 0;

  unsigned int *fpga_dma = static_cast<unsigned int *>(mmap(NULL, 16*sizeof(unsigned int), PROT_READ|PROT_WRITE, MAP_SHARED, fd_, 0x7E200000));

for(int i = 0; i < num_output; i++) {
  quantize(large_mat + i*num_input, qlarge_mat + i*((num_input-1)/4+1), num_input, weight_bits_min, weight_bits_max, weight_offset, weight_scale);
}

  for (int i = 0; i < num_output; ++i)
	qoutput[i] = 0;

  for (int i = 0; i < num_output; i += m_size_)
  {
    for (int j = 0; j < ((num_input-1)/4+1); j += v_size_)
    {
      // 0) Initialize input vector
      int block_row = min(m_size_, num_output - i);
      int block_col = min(v_size_, ((num_input-1)/4 + 1) - j);

      // 1) Assign a vector
      memcpy(vec, qinput + j, sizeof(float)*block_col);
      memset(vec + block_col, 0, sizeof(float)*(v_size_ - block_col));

      // 2) Assign a matrix
      for(int row = 0; row < block_row; ++row) {
      	memcpy(mat + v_size_*row, qlarge_mat + j + ((num_input-1)/4+1)*(i+row), sizeof(float)*block_col);
      }

  *(fpga_dma+6) = 0x10000000;
  *(fpga_dma+8) = 0xC0000000;
  *(fpga_dma+10) = 4160;
  while ((*(fpga_dma+1) & 0x00000002) == 0);

      // 3) Call a function qblockMV() to execute MV multiplication
      const int* ret = this->qblockMV(comp);

  *(fpga_dma+6) = 0xC0000000;
  *(fpga_dma+8) = 0x10000000;
  *(fpga_dma+10) = 256;
  while ((*(fpga_dma+1) & 0x00000002) == 0);

      // 4) Accumulate intermediate results
      for(int row = 0; row < block_row; ++row)
        qoutput[i + row] += ret[row];

    }
  }

  munmap(fpga_dma, 16*sizeof(unsigned int));

  dequantize(qoutput, output, num_output, 0, act_scale*weight_scale);
}

void FPGA::convLowering(const std::vector<std::vector<std::vector<std::vector<float>>>> &cnn_weights,
                        std::vector<std::vector<float>> &new_weights,
                        const std::vector<std::vector<std::vector<float>>> &inputs,
                        std::vector<std::vector<float>> &new_inputs)
{
  /*
   * Arguments:
   *
   * conv_weights: [conv_channel, input_channel, conv_height, conv_width]
   * new_weights: [?, ?]
   * inputs: [input_channel, input_height, input_width]
   * new_inputs: [?, ?]
   *
   */

  int conv_channel = cnn_weights.size();
  int input_channel = cnn_weights[0].size();
  int conv_height = cnn_weights[0][0].size();
  int conv_width = cnn_weights[0][0][0].size();
  //int input_channel = inputs.size();
  int input_height = inputs[0].size();
  int input_width = inputs[0][0].size();

  // IMPLEMENT THIS
  // For example,
  // new_weights[0][0] = cnn_weights[0][0][0][0];
  // new_inputs[0][0] = inputs[0][0][0];

  for(int i = 0; i < conv_channel; i++) {
    for(int j = 0; j < input_channel; j++) {
      for(int k = 0; k < conv_height; k++) {
        for(int l = 0; l < conv_width; l++) {
          new_weights[i][j*conv_height*conv_width+k*conv_width+l] = cnn_weights[i][j][k][l];
        }
      }
    }
  }

  for(int r = 0; r < input_height-conv_height+1; r++) {
    for(int c = 0; c < input_width-conv_width+1; c++) {
      for(int i = 0; i < input_channel; i++) {
        for(int sub_r = 0; sub_r < conv_height; sub_r++) {
          for(int sub_c = 0; sub_c < conv_width; sub_c++) {
            new_inputs[i*conv_height*conv_width+sub_r*conv_width+sub_c][r*(input_width-conv_width+1)+c] = inputs[i][r+sub_r][c+sub_c];
          }
        }
      }
    }
  }

}
