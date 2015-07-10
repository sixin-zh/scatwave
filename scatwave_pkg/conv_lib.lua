local conv_lib={}
local tools=require 'tools'
local ffi=require 'ffi'
local fftw = require 'fftw3'
local fftw_complex_cast = 'fftw_complex*'
local tools=require 'tools'

local complex = require 'complex'

function conv_lib.my_convolution_2d(x,filt,ds)
   assert(tools.is_complex(x),'The signal should be complex')
   assert(tools.are_equal_dimension(x,filt),'The signal should be of the same size')
   assert(x:size(1) % 2^ds ==0,'First dimension should be a multiple of 2^2ds')
   assert(x:size(2) % 2^ds ==0,'First dimension should be a multiple of 2^2ds')   
   local yf=complex.multiply_complex_tensor(x,filt)
   yf=conv_lib.periodize_along_k(conv_lib.periodize_along_k(yf,1,ds),2,ds)
   
   return conv_lib.my_fft_complex(conv_lib.my_fft_complex(yf,1,1),2,1)
end


-- Apply a symetric padding -- assuming the signal is real
function conv_lib.pad_signal_along_k(x,new_size_along_k,k)
   
   local fs=torch.LongStorage(x:nDimension())
   for l=1,x:nDimension() do
      if(l==k) then
         fs[l]=new_size_along_k
         else
         fs[l]=x:size(l)
      end
   end
   
   local id_tmp=torch.cat(torch.range(1,x:size(k),1):long(),torch.range(x:size(k),1,-1):long())
   
   local idx=torch.LongTensor(new_size_along_k)
   local n_decay=torch.floor((new_size_along_k-x:size(k))/2)
   for i=1,new_size_along_k do
      idx[i]=(id_tmp[(i-n_decay-1)%id_tmp:size(1)+1])
   end
   

local y=torch.Tensor(fs)

 y:index(x,k,idx)   

   return y
end

-- un pad sihgnlas that have been padded with symmetric signals
function conv_lib.unpad_signal_along_k(x,original_size_along_k,k,res)
   --local n_decay=torch.floor((x:size(k)-original_size_along_k)/2)+1
   

   local n_decay=torch.floor((x:size(k)*2^res-original_size_along_k)/2^(res+1))
   
   local f_size_along_k=1+torch.floor((original_size_along_k-1)/(2^res))


local y=torch.Tensor.narrow(x,k,n_decay+1,f_size_along_k)
--local y=torch.Tensor.narrow(x,k,n_decay,original_size_along_k)

   return y
end



function conv_lib.periodize_along_k(h,k,l)
      assert(k<=h:nDimension(),'k is bigger than the dimension')
   local dim=h:size()
   
   local final_dim=torch.LongStorage(#dim)
   local new_dim=torch.LongStorage(#dim+1)
   for i=1,k-1 do
      new_dim[i]=dim[i]
      final_dim[i]=dim[i]
   end
   
   new_dim[k]=2^l
   final_dim[k]=dim[k]/2^l
   new_dim[k+1]=dim[k]/2^l
   for i=k+1,#dim do
      new_dim[i+1]=dim[i]
      final_dim[i]=dim[i]
   end
   
   local reshaped_h=torch.view(h,new_dim)
   
   local  summed_h=torch.view(torch.sum(reshaped_h,k),final_dim)
   return summed_h
end


-- to use for real signals
function conv_lib.my_fft_real(x,k)   
   assert(not tools.is_complex(x),'Signal is not real')
   assert(k<=x:nDimension(),'k is bigger than the dimension')
   local input=x
   
   --- Parameters of the fft PLAN
   local rank=1
   
   local n=torch.LongTensor({{x:size(k)}})
   local n_data=torch.data(n)
   local n_data_cast= ffi.cast('const int*',n_data)

   
   local howmany=x:nElement()/x:size(k)  

      
      input = input:contiguous() -- make sure input is contiguous
   local input_data = torch.data(input)
   local input_data_cast = ffi.cast('double*', input_data)
   
   local inembed_data_cast=n_data_cast--ffi.cast('const int*',0)
      
   local istride=x:stride(k)
   local idist=x:nElement()/(x:stride(k)*x:size(k))



   local fs=torch.LongStorage(x:nDimension()+1)
   for l=1,x:nDimension() do
      fs[l]=x:size(l)
   end
   fs[x:nDimension()+1]=2
   
   local output = torch.Tensor(fs):typeAs(input):zero()
   
   local output_data = torch.data(output);
   local output_data_cast = ffi.cast(fftw_complex_cast, output_data)
   
   local oembed_data_cast=n_data_cast--ffi.cast('const int*',oembed_data)
      
   local ostride=istride
   local odist=idist
   
   
   local flags = fftw.ESTIMATE
   
   local plan  = fftw.plan_many_dft_r2c(rank,n_data_cast,howmany,input_data_cast,inembed_data_cast,
                                        istride,idist,output_data_cast,oembed_data_cast,ostride,odist,flags)   

     -- fftw.execute(plan)
   
   
   -- le premier, -1, le deuxieme
   
   
   local n_el=   torch.floor((x:size(k)-1)/2)
   local n_med= 2+torch.floor((x:size(k))/2)
   
   
   output:narrow(k,n_med,n_el):indexCopy(k,torch.range(n_el,1,-1):long(),output:narrow(k,2,n_el))
   
   output:narrow(k,torch.ceil(x:size(k)/2)+1,torch.floor(x:size(k)/2)):narrow(output:nDimension(),2,1):mul(-1)
   
   fftw.destroy_plan(plan)
   
   return output
end

-- to use for real signals
function conv_lib.my_fft_complex(x,k,backward) 
   
   assert(tools.is_complex(x),'Signal is not complex')
   assert(k<x:nDimension(),'k is bigger than the dimension')  
   local input
   local flag=backward or false      
      input=x
   local rank=1
   
   local n=torch.LongTensor({{x:size(k)}})
   local n_data=torch.data(n)
   local n_data_cast= ffi.cast('const int*',n_data)
   
   
   local howmany=x:nElement()/(2*x:size(k))   
      
      input = input:contiguous() -- make sure input is contiguous
   local input_data = torch.data(input)
   local input_data_cast = ffi.cast(fftw_complex_cast, input_data)
   
   --local inembed=nil
   --local inembed_data=torch.data(inembed)
   local inembed_data_cast=n_data_cast--ffi.cast('const int*',0)
      
      --local istride=1
      --for l=1,k-1 do
      --  istride=istride*x:size(l)
      --end 
      
      --local idist=1
      --for l=k+1,x:nDimension()-1 do
      --  idist=idist*x:size(l)
      --end 
      
   local idist=x:nElement()/(x:stride(k)*x:size(k)) 
      
   local istride=x:stride(k)/2
   
   
   local output = torch.Tensor(input:size()):typeAs(input):zero()
   
   local output_data = torch.data(output);
   local output_data_cast = ffi.cast(fftw_complex_cast, output_data)
   
   --  local oembed=nil
   --   local oembed_data=torch.data(oembed)
   local oembed_data_cast=n_data_cast--ffi.cast('const int*',oembed_data)
      
   local ostride=istride
   local odist=idist
   
   local sign
   if not backward then
      sign=fftw.FORWARD
   else
      sign=fftw.BACKWARD
   end
   
   
   
   
   
   local flags = fftw.ESTIMATE
   
--[[--
    
    --
    -- [[--local plan  = fftw.plan_dft_2d(input:size(1), input:size(2), 
    --                            input_data_cast, output_data_cast, direction, flags)
    
    
    --]]
   local plan  = fftw.plan_many_dft(rank,n_data_cast,howmany,input_data_cast,inembed_data_cast,
                                    istride,idist,output_data_cast,oembed_data_cast,ostride,odist,sign,flags)   
      
      fftw.execute(plan)
   
   fftw.destroy_plan(plan)
   
   if(flag) then
      output=torch.div(output,x:size(k))   
   end
   
   return output
end

return conv_lib