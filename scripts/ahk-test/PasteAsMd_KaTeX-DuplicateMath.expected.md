> ### Where it appears
>
> For a thin flat plate of thickness `t_s`, the plate bending stiffness is:
>
> ```math
> D_{plate} = \frac{E\,t_s^3}{12(1-\nu^2)}
> ```
>
> The classical elastic buckling stress under in-plane compression has the form:
>
> ```math
> \sigma_{cr} = k_c \cdot \frac{\pi^2\,D_{plate}}{b^2\,t_s}
> ```
>
> Equivalently (substitute $`D_{plate}`$):
>
> ```math
> \sigma_{cr} = k_c \cdot \frac{\pi^2 E}{12(1-\nu^2)}\left(\frac{t_s}{b}\right)^2
> ```
>
> - `b` here is your characteristic bay width (rib-to-rib span), which you’re modelling as `b(M) = l_max / 2^M`.
