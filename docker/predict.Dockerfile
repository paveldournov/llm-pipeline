# Copyright 2022 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


FROM gcr.io/deeplearning-platform-release/pytorch-gpu.1-12

WORKDIR /home/jupyter

COPY scripts/clean_up_torch_xla.sh .
COPY scripts/install.sh .
RUN ./install.sh

COPY src/predict.py .

ENV FLASK_APP=predict
ENV SERVER_HOST=0.0.0.0

RUN pip install Flask

ENTRYPOINT [ "deepspeed", "predict.py"]