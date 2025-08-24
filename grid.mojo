# ===----------------------------------------------------------------------=== #
# Copyright (c) 2025, Modular Inc. All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #

import random
from collections import Optional
from algorithm import parallelize

from memory import memcpy, memset_zero


struct Grid[rows: Int, cols: Int](Copyable, Movable, Stringable):
    # ===-------------------------------------------------------------------===#
    # Fields
    # ===-------------------------------------------------------------------===#

    alias num_cells = rows * cols * 3
    var data: UnsafePointer[Int8]

    # ===-------------------------------------------------------------------===#
    # Life cycle methods
    # ===-------------------------------------------------------------------===#

    fn __init__(out self):
        self.data = UnsafePointer[Int8].alloc(self.num_cells)
        memset_zero(self.data, self.num_cells)

    fn __copyinit__(out self, existing: Self):
        self.data = UnsafePointer[Int8].alloc(self.num_cells)
        memcpy(dest=self.data, src=existing.data, count=self.num_cells)
        # The lifetime of `existing` continues unchanged

    fn __del__(deinit self):
        for i in range(self.num_cells):
            (self.data + i).destroy_pointee()
        self.data.free()

    # ===-------------------------------------------------------------------===#
    # Factory methods
    # ===-------------------------------------------------------------------===#

    @staticmethod
    fn random(seed: Optional[Int] = None) -> Self:
        grid = Self()
        if seed:
            random.seed(seed.value())
        else:
            random.seed()

        random.randint(grid.data, rows * cols * 3, 0, 3)
        for i in range(grid.num_cells):
            var value = grid.data[i]
            if value > 1:
                grid.data[i] = 0

        return grid

    # ===-------------------------------------------------------------------===#
    # Indexing
    # ===-------------------------------------------------------------------===#

    fn __getitem__(self, row: Int, col: Int, layer: Int) -> Int8:
        return (self.data + row * cols + col + (layer * rows * cols))[]

    fn __setitem__(
        mut self, row: Int, col: Int, layer: Int, value: Int8
    ) -> None:
        (self.data + row * cols + col + (layer * rows * cols))[] = value

    # ===-------------------------------------------------------------------===#
    # Trait implementations
    # ===-------------------------------------------------------------------===#

    fn __str__(self) -> String:
        str = String()
        for layer in range(3):
            for row in range(rows):
                for col in range(cols):
                    if self[row, col, layer] == 1:
                        str += "*"
                    else:
                        str += " "
                str += "\n"
        return str

    # ===-------------------------------------------------------------------===#
    # Methods
    # ===-------------------------------------------------------------------===#

    fn evolve(self) -> Self:
        next_generation = Self()

        fn calc_num_neighbors(
            self: Self,
            row_above: Int,
            row: Int,
            row_below: Int,
            col_left: Int,
            col: Int,
            col_right: Int,
            layer: Int,
        ) -> Int8:
            # Calculate the number of populated neighbors around the cell at (row, col)
            return (
                self[row_above, col_left, layer]
                + self[row_above, col, layer]
                + self[row_above, col_right, layer]
                + self[row, col_left, layer]
                + self[row, col_right, layer]
                + self[row_below, col_left, layer]
                + self[row_below, col, layer]
                + self[row_below, col_right, layer]
            )

        @parameter
        fn worker(row: Int) -> None:
            for layer in range(3):
                # Calculate neighboring row indices, handling "wrap-around"
                row_above = (row - 1) % rows
                row_below = (row + 1) % rows
                for col in range(cols):
                    # Calculate neighboring column indices, handling "wrap-around"
                    col_left = (col - 1) % cols
                    col_right = (col + 1) % cols

                    # Determine number of populated cells around the current cell
                    num_neighbors = calc_num_neighbors(
                        self,
                        row_above,
                        row,
                        row_below,
                        col_left,
                        col,
                        col_right,
                        layer,
                    )
                    var layer_before = (layer + 1) % 3
                    num_neighbors_before = calc_num_neighbors(
                        self,
                        row_above,
                        row,
                        row_below,
                        col_left,
                        col,
                        col_right,
                        layer_before,
                    )
                    var layer_behind = (layer - 1) % 3
                    num_neighbors_behind = calc_num_neighbors(
                        self,
                        row_above,
                        row,
                        row_below,
                        col_left,
                        col,
                        col_right,
                        layer_behind,
                    )

                    var parasites = (
                        num_neighbors_before + self[row, col, layer_before]
                    )
                    var symbionts = (
                        num_neighbors_behind + self[row, col, layer_behind]
                    )
                    var neighbors_value = num_neighbors + symbionts - parasites

                    var birth = neighbors_value >= 3 and neighbors_value <= 3
                    var survive = neighbors_value >= 3 and neighbors_value <= 5

                    if (survive and self[row, col, layer] == 1) or (
                        birth and self[row, col, layer] == 0
                    ):
                        next_generation[row, col, layer] = 1

        # Parallelize the evolution of rows across available CPU cores
        parallelize[worker](rows)

        return next_generation
