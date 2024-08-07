import { create } from "zustand";
import produce from "immer";
import { devtools } from "zustand/middleware";

interface StoreState {
  address: string;
  setAddress: (address: string) => void;
  currentTime: number;
  setCurrentTime: (currentTime: number) => void;
}

const useUserStore = create<StoreState>((set) => ({
  address: "",
  setAddress: (address) =>
    set((state) => ({
      ...state,
      address,
    })),
  currentTime: Math.floor(Date.now() / 1000),
  setCurrentTime: (currentTime) =>
    set((state) => ({
      ...state,
      currentTime,
    })),
}));

export default useUserStore;
